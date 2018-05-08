#!/bin/bash
url="https://$DOCKER_REPO/v2/${CIRCLE_PROJECT_REPONAME}"
accept_header="Accept:application/vnd.docker.distribution.manifest.v2+json"
number_of_commits=5

declare -a tags=("$(curl -s $url/tags/list -u $DOCKER_USER:$DOCKER_PASS | jq -r '.tags')")

last_tags=$(git log -n $number_of_commits --pretty=format:"%H")
last_tags_arr=(${last_tags[0]} 'master' 'latest')

for tag in $(echo "${tags}" | jq -r '.[]'); do
	if [[ ! " ${last_tags_arr[@]} " =~ " ${tag} " ]]; then
		digest_hash="$(curl -s $url/manifests/$tag -u $DOCKER_USER:$DOCKER_PASS --header $accept_header -i | grep Docker-Content-Digest:| awk {'print $2'})"
		digest_hash=${digest_hash%$'\r'}
		$(curl $url/manifests/$digest_hash -u $DOCKER_USER:$DOCKER_PASS -X DELETE --header $accept_header)
	fi
done
