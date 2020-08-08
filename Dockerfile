FROM alpine:latest

# install dependencies
RUN apk add --no-cache bash curl grep zip jq git subversion mercurial
RUN apk add --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/testing/ pandoc

# copy release.sh
ADD ./release.sh /usr/local/bin/

# make release.sh executable
RUN chmod +x /usr/local/bin/release.sh
