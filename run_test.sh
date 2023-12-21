#!/bin/bash

oneTimeSetUp() {
  docker rm -f nginx-httpbin | true
  docker run -d -p 127.0.0.1:10080:80  --name nginx-httpbin kennethreitz/httpbin
  cp `pwd`/test/test.conf ./nginx/conf/nginx.conf
  pkill nginx
  nginx/objs/nginx -p `pwd`/nginx &
  while ! nc -z localhost 1234; do
    sleep 0.1
  done

  while ! nc -z localhost 10080; do
    sleep 0.1
  done

  docker logs -f nginx-httpbin &
  echo "Waiting for nginx to start..."
  sleep 3
}

oneTimeTearDown() {
  docker rm -f nginx-httpbin | true
  pkill nginx | true
}

test_delete_prefix() {
  # normal case
  local result=$(curl -s -b'example_prefix_a=1' -b'not_match_prefix_b=2' http://localhost:1234/get -L -i)
  assertContains "$result" "$result" '"a=1;not_match_prefix_b=2"'
  # for no value
  local result=$(curl -s -b'example_prefix_a=1' -b'example_prefix_b=' -b'example_prefix_c=' http://localhost:1234/get -L -i)
  assertContains "$result" "$result" '"a=1;b=;c="'
  # for no value and no trailing semicolon
  local result=$(curl -s -b'example_prefix_a=1;' -b'example_prefix_b=;' -b'example_prefix_c=;' http://localhost:1234/get -L -i)
  assertContains "$result" "$result" '"a=1;;b=;;c=;"'
}

test_delete_prefix_with_header() {
  # normal case
  local result=$(curl -s -H 'cookie: example_prefix_a=1; not_match_prefix_b=2;' http://localhost:1234/get -L -i)
  assertContains "$result" "$result" '"a=1; not_match_prefix_b=2;"'
  # for no value
  local result=$(curl -s -H 'cookie: example_prefix_a=1; example_prefix_b=; example_prefix_c=;' http://localhost:1234/get -L -i)
  assertContains "$result" "$result" '"a=1; b=; c=;"'
  # for no value and no trailing semicolon
  local result=$(curl -s -H 'cookie: example_prefix_a=1;; example_prefix_b=;; example_prefix_c=;;' http://localhost:1234/get -L -i)
  assertContains "$result" "$result" '"a=1;; b=;; c=;;"'
}

test_append_prefix() {
  local result=$(curl http://localhost:1234/cookies/set/foo/bar -L -i)
  assertContains "$result" "$result" 'example_prefix_foo=bar; Path=/'
}

test_delete_long_cookie_with_request() {
  local long_value=$(printf 'a%.0s' {1..1000}) # 1000文字の 'a' で構成される文字列
  local result=$(curl -s -b"example_prefix_$long_value=1" http://localhost:1234/get -L -i)
  assertContains "$result" "$result" "$long_value=1"
}

test_delete_many_cookies_with_request() {
  local cookies=()
  for i in {1..100}; do
    cookies+=("-b" "example_prefix_name${i}=${i}")
    expected+=("name${i}=${i};")
  done


  local result=$(curl -s "${cookies[@]}" http://localhost:1234/get -L -i)
  assertContains "$result" "$result" "${expected/%?/}"
}

test_many_cookies_with_response() {
  local query_params=""
  for i in $(seq 1 100); do
    query_params+="name${i}=value${i}&"
  done

  local result=$(curl -s -i -L "http://localhost:1234/cookies/set?$query_params")
  for i in $(seq 1 100); do
    assertContains "$result" "$result" "Set-Cookie: example_prefix_name${i}=value${i}; Path=/"
  done
}

test_large_cookie_value_with_response() {
  local large_value=$(printf 'a%.0s' {1..1000}) # 1000文字の 'a' で構成される文字列
  local result=$(curl -s -i -L "http://localhost:1234/cookies/set?large_cookie=$large_value")
  assertContains "$result" "$result" "Set-Cookie: example_prefix_large_cookie=$large_value; Path=/"
}


. tmp/shunit2/shunit2
