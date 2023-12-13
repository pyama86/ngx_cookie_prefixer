#!/bin/bash

oneTimeSetUp() {
  docker rm -f nginx-httpbin | true
  docker run -d -p 127.0.0.1:10080:80  --name nginx-httpbin kennethreitz/httpbin
  cp `pwd`/test/test.conf ./nginx/conf/nginx.conf
  pkill nginx
  nginx/objs/nginx -p `pwd`/nginx &
  sleep 1
}

oneTimeTearDown() {
  docker rm -f nginx-httpbin
  pkill nginx
}

test_delete_@refix() {
  local result=$(curl -s -b'name=example_prefix_a; value=1' -b'name=not_match_prefix_b; value=2;' http://localhost:1234/get -L -i)
  assertContains "$result" 'name=a; value=1'
  assertContains "$result" 'name=not_match_prefix_b; value=2'
}

test_append_prefix() {
  local result=$(curl http://localhost:1234/cookies/set/foo/bar -L -i)
  assertContains "$result" 'example_prefix_foo=bar; Path=/'
}

. tmp/shunit2/shunit2
