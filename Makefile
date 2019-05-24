SHELL=/bin/bash
SSH_KEY=${HOME}/.ssh/aurelian-one-bot-key

## Display a list of the documented make targets
.PHONY: help
help:
	@echo Documented Make targets:
	@perl -e 'undef $$/; while (<>) { while ($$_ =~ /## (.*?)(?:\n# .*)*\n.PHONY:\s+(\S+).*/mg) { printf "\033[36m%-30s\033[0m %s\n", $$2, $$1 } }' $(MAKEFILE_LIST) | sort

## Run build, test, and package step
.PHONY: build
build:
	mvn verify

## Release new version
.PHONY: release
release: old_version = $(shell mvn -q -Dexec.executable="echo" -Dexec.args='$${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec 2>/dev/null)
release: git_branch := $(shell git rev-parse --abbrev-ref HEAD)
release: new_version = $(subst -SNAPSHOT,,$(old_version))
release: dev_version = $(shell echo $(new_version) | cut -d '.' -f1,2).$(shell expr $(shell echo $(new_version) | cut -d '.' -f3) + 1)-SNAPSHOT
release: $(SSH_KEY)
	@echo Releasing $(old_version) from $(git_branch) as $(new_version) / $(dev_version)..
	
	# ensure dependencies use release versions
	@mvn versions:use-releases

	# write release version to POM
	@mvn versions:set -DnewVersion=$(new_version)

	# setup git
	@git config user.name "aurelian-one-bot [Via CircleCI]"
	@git config user.email "aurelian-one-bot@ben.meierhost.com"

	@git add pom.xml **/pom.xml
	@git commit -m "Release: $(new_version)"
	@git tag "$(new_version)"

	# land on master and publish
	@git checkout master
	@git merge --no-edit $(git_branch)

	@GIT_SSH_COMMAND="ssh -i $(SSH_KEY) -o IdentitiesOnly=yes" \
		git push origin master --tags

	@git checkout develop
	@git merge --no-edit $(git_branch)
	@mvn versions:set -DnewVersion=$(dev_version)
	@git add pom.xml **/pom.xml
	@git commit -m "Changed: bumped pom version to $(dev_version)"
	@GIT_SSH_COMMAND="ssh -i $(SSH_KEY) -o IdentitiesOnly=yes" \
		git push origin develop

$(SSH_KEY):
ifndef ENCODED_PRIVATE_KEY
	$(error ENCODED_PRIVATE_KEY is undefined)
endif
	@echo $${ENCODED_PRIVATE_KEY} | base64 -d > $@
	@chmod 0600 $@
	@ls -alh $@