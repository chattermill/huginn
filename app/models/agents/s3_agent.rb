module Agents
  class S3Agent < Agent
    include FormConfigurable
    include FileHandling

    EVENT_TYPES = %w[added modified removed].freeze

    emits_file_pointer!
    no_bulk_receive!

    default_schedule 'every_1h'

    gem_dependency_check { defined?(Aws::S3) }

    description do
      <<-MD
        The S3Agent can watch a bucket for changes or emit an event for every file in that bucket. When receiving events, it writes the data into a file on S3.

        #{'## Include `aws-sdk-core` in your Gemfile to use this Agent!' if dependencies_missing?}

        `mode` must be present and either `read` or `write`, in `read` mode the agent checks the S3 bucket for changed files, with `write` it writes received events to a file in the bucket.

        ### Universal options

        To use credentials for the `access_key` and `access_key_secret` use the liquid `credential` tag like so `{% credential name-of-credential %}`

        Select the `region` in which the bucket was created.

        ### Reading

        When `watch` is set to `true` the S3Agent will watch the specified `bucket` for changes. An event will be emitted for every detected change.
        If an `event_type` option is selected, S3Agent will emit only that type of detected change (`added`, `modified`, or `removed`), it can
        be left in blank to emit all.

        Also you can watch files that match a `prefix` or `suffix`. For example
        you can set `prefix` with `Data2017` and S3Agent will only watch file names that begin with that expresion
        (e.g. `Data2017January.csv` will be watched but `Data2015May.csv` won't)

        When `watch` is set to `false` the agent will emit an event for every file in the bucket on each sheduled run.

        #{emitting_file_handling_agent_description}

        ### Writing

        Specify the filename to use in `filename`, Liquid interpolation is possible to change the name per event.

        Use [Liquid](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid) templating in `data` to specify which part of the received event should be written.
      MD
    end

    event_description do
      "Events will looks like this:\n\n    %s" % if boolify(interpolated['watch'])
        Utils.pretty_print({
          "file_pointer" => {
            "file" => "filename",
            "agent_id" => id
          },
          "event_type" => "modified/added/removed"
        })
      else
        Utils.pretty_print({
          "file_pointer" => {
            "file" => "filename",
            "agent_id" => id
          }
        })
      end
    end

    def default_options
      {
        'mode' => 'read',
        'access_key_id' => '',
        'access_key_secret' => '',
        'watch' => 'true',
        'bucket' => "",
        'event_type' => 'added',
        'data' => '{{ data }}'
      }
    end

    form_configurable :mode, type: :array, values: %w(read write)
    form_configurable :access_key_id, roles: :validatable
    form_configurable :access_key_secret, roles: :validatable
    form_configurable :region, type: :array, values: %w(us-east-1 us-west-1 us-west-2 eu-west-1 eu-central-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 ap-northeast-2 sa-east-1)
    form_configurable :watch, type: :array, values: %w(true false)
    form_configurable :bucket, roles: :completable
    form_configurable :prefix
    form_configurable :suffix
    form_configurable :event_type, type: :array, values: EVENT_TYPES
    form_configurable :filename
    form_configurable :data

    def validate_options
      if options['mode'].blank? || !['read', 'write'].include?(options['mode'])
        errors.add(:base, "The 'mode' option is required and must be set to 'read' or 'write'")
      end
      if options['bucket'].blank?
        errors.add(:base, "The 'bucket' option is required.")
      end
      if options['region'].blank?
        errors.add(:base, "The 'region' option is required.")
      end

      case interpolated['mode']
      when 'read'
        if options['watch'].blank? || ![true, false].include?(boolify(options['watch']))
          errors.add(:base, "The 'watch' option is required and must be set to 'true' or 'false'")
        end

        if options['event_type'].present? && !options['event_type'].in?(EVENT_TYPES)
          errors.add(:base, "The 'event_type' option must be set to 'added, 'modified' or 'removed'")
        end
      when 'write'
        if options['filename'].blank?
          errors.add(:base, "filename must be specified in 'write' mode")
        end
        if options['data'].blank?
          errors.add(:base, "data must be specified in 'write' mode")
        end
      end
    end

    def validate_access_key_id
      !!buckets
    end

    def validate_access_key_secret
      !!buckets
    end

    def complete_bucket
      (buckets || []).collect { |room| {text: room.name, id: room.name} }
    end

    def working?
      checked_without_error?
    end

    def check
      return if interpolated['mode'] != 'read'
      safely do
        contents = get_bucket_contents
        if boolify(interpolated['watch'])
          watch(contents)
        else
          contents.each do |key, _|
            create_event payload: get_file_pointer(key)
          end
        end
      end
    end

    def get_io(file)
      client.get_object(bucket: interpolated['bucket'], key: file).body
    end

    def receive(incoming_events)
      return if interpolated['mode'] != 'write'
      incoming_events.each do |event|
        safely do
          mo = interpolated(event)
          client.put_object(bucket: mo['bucket'], key: mo['filename'], body: mo['data'])
        end
      end
    end

    private

    def safely
      yield
    rescue Aws::S3::Errors::AccessDenied => e
      error("Could not access '#{interpolated['bucket']}' #{e.class} #{e.message}")
    rescue Aws::S3::Errors::ServiceError =>e
      error("#{e.class}: #{e.message}")
    end

    def watch(contents)
      if last_check_at.nil?
        self.memory['seen_contents'] = contents
        return
      end

      new_memory = contents.dup

      (memory['seen_contents'] || {}).each do |key, etag|
        next unless process_file?(key)

        if contents[key].blank? && emit_event?(:removed)
          create_event payload: get_file_pointer(key).merge(event_type: :removed)
        elsif contents[key] != etag && emit_event?(:modified)
          create_event payload: get_file_pointer(key).merge(event_type: :modified)
        end
        contents.delete(key)
      end

      if emit_event?(:added)
        contents.each do |key, etag|
          next unless process_file?(key)
          create_event payload: get_file_pointer(key).merge(event_type: :added)
        end
      end

      self.memory['seen_contents'] = new_memory
    end

    def get_bucket_contents
      contents = {}
      client.list_objects(bucket: interpolated['bucket']).each do |response|
        response.contents.each do |file|
          contents[file.key] = file.etag
        end
      end
      contents
    end

    def client
      @client ||= Aws::S3::Client.new(credentials: Aws::Credentials.new(interpolated['access_key_id'], interpolated['access_key_secret']),
                                      region: interpolated['region'])
    end

    def buckets(log = false)
      @buckets ||= client.list_buckets.buckets
    rescue Aws::S3::Errors::ServiceError => e
      false
    end

    def emit_event?(event_type)
      event_filter = interpolated['event_type']
      return true if event_filter.blank?

      event_filter == event_type.to_s
    end

    def process_file?(file_name)
      prefix_match?(file_name) && suffix_match?(file_name)
    end

    def prefix_match?(file_name)
      prefix = interpolated['prefix']
      prefix.blank? || file_name.starts_with?(prefix)
    end

    def suffix_match?(file_name)
      suffix = interpolated['suffix']
      suffix.blank? || file_name.ends_with?(suffix)
    end
  end
end
