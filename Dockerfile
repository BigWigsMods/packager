FROM debian:9

# install dependencies
RUN apt-get update && \
	apt-get install -y curl zip jq pandoc git subversion mercurial

# copy release.sh
ADD release.sh /usr/local/bin/

# make release.sh executable
RUN chmod +x /usr/local/bin/release.sh
