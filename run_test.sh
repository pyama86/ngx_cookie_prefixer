#!/bin/bash
oneTimeSetUp() {
  docker rm -f nginx-httpbin | true
  docker run -d -p 127.0.0.1:10080:80 --name nginx-httpbin kennethreitz/httpbin
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
  local result=$(curl -s -b'example_prefix_a=1' -b'not_match_prefix_b=2' http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" '"a=1;not_match_prefix_b=2"'
  # for no value
  local result=$(curl -s -b'example_prefix_a=1' -b'example_prefix_b=' -b'example_prefix_c=' http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" '"a=1;b=;c="'
  # for no value and no trailing semicolon
  local result=$(curl -s -b'example_prefix_a=1;' -b'example_prefix_b=;' -b'example_prefix_c=;' http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" '"a=1;;b=;;c=;"'
}

test_delete_prefix_with_header() {
  # normal case
  local result=$(curl -s -H 'cookie: example_prefix_a=1; not_match_prefix_b=2;' http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" '"a=1; not_match_prefix_b=2;"'
  # for no value
  local result=$(curl -s -H 'cookie: example_prefix_a=1; example_prefix_b=; example_prefix_c=;' http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" '"a=1; b=; c=;"'
  # for no value and no trailing semicolon
  local result=$(curl -s -H 'cookie: example_prefix_a=1;; example_prefix_b=;; example_prefix_c=;;' http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" '"a=1;; b=;; c=;;"'
}

test_append_prefix() {
  local result=$(curl http://localhost:1234/example_prefix/cookies/set/foo/bar -i)
  assertContains "$result" "$result" 'example_prefix_foo=bar; Path=/'
}

test_delete_long_cookie_with_request() {
  local long_value=$(printf 'a%.0s' {1..1000}) # 1000文字の 'a' で構成される文字列
  local result=$(curl -s -b"example_prefix_$long_value=1" http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" "$long_value=1"
}

test_delete_many_cookies_with_request() {
  local cookies=()
  for i in {1..100}; do
    cookies+=("-b" "example_prefix_name${i}=${i}")
    expected+=("name${i}=${i};")
  done


  local result=$(curl -s "${cookies[@]}" http://localhost:1234/example_prefix/get -i)
  assertContains "$result" "$result" "${expected/%?/}"
}

test_many_cookies_with_response() {
  local query_params=""
  for i in $(seq 1 100); do
    query_params+="name${i}=value${i}&"
  done

  local result=$(curl -s -i "http://localhost:1234/example_prefix/cookies/set?$query_params")
  for i in $(seq 1 100); do
    assertContains "$result" "$result" "Set-Cookie: example_prefix_name${i}=value${i}; Path=/"
  done
}

test_large_cookie_value_with_response() {
  local large_value=$(printf 'a%.0s' {1..1000}) # 1000文字の 'a' で構成される文字列
  local result=$(curl -s -i "http://localhost:1234/example_prefix/cookies/set?large_cookie=$large_value")
  assertContains "$result" "$result" "Set-Cookie: example_prefix_large_cookie=$large_value; Path=/"
}

test_delete_many_cookies_with_fuzzing() {
  local cookies=()
  local expected=()

  for i in {1..100}; do
    # ランダムな文字数を生成 (例: 1〜15の範囲)
    local len=$((RANDOM % 14 + 1))

    # ロケールを C に設定して、ランダムな文字列を生成
    local rand_str=$(LC_ALL=C dd bs=512 if=/dev/urandom count=1 | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1)

    # プレフィックスをランダムに選択
    local prefix=""
    if (( RANDOM % 2 )); then
      prefix="example_prefix_"
    fi

    # クッキーと期待値を配列に追加
    cookies+=("-b" "${prefix}name${i}=${rand_str}")
    expected+=("name${i}=${rand_str};")
  done

  # cURL コマンドの実行
  local result=$(curl -s "${cookies[@]}" http://localhost:1234/example_prefix/get -i)

  # 結果のアサーション
  assertContains "$result" "$result" "${expected/%?/}"
}

test_delete_many_cookies_with_fuzzing_and_shortprefix() {
  local cookies=()
  local expected=()

  for i in {1..100}; do
    # ランダムな文字数を生成 (例: 1〜15の範囲)
    local len=$((RANDOM % 14 + 1))

    # ロケールを C に設定して、ランダムな文字列を生成
    export LC_ALL=C
    local rand_str=$(dd bs=512 if=/dev/urandom count=1 | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1)

    # プレフィックスをランダムに選択
    local prefix=""
    if (( RANDOM % 2 )); then
      prefix="a"
    fi

    # クッキーと期待値を配列に追加
    cookies+=("-b" "${prefix}name${i}=${rand_str}")
    expected+=("name${i}=${rand_str};")
  done

  # cURL コマンドの実行
  local result=$(curl -s "${cookies[@]}" http://localhost:1234/a/get -i)

  # 結果のアサーション
  assertContains "$result" "$result" "${expected/%?/}"
}

test_many_cookies_with_fuzzing() {
  local query_params=""
  local values=()

  # ランダムな値を生成して配列に格納
  for i in $(seq 1 100); do
    local len=$((RANDOM % 14 + 1))
    values[i]=$(LC_ALL=C dd bs=512 if=/dev/urandom count=1 | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1)
    query_params+="name${i}=${values[i]}&"
  done

  # cURL コマンドの実行
  local result=$(curl -i "http://localhost:1234/example_prefix/cookies/set?$query_params")

  # 結果の検証
  for i in $(seq 1 100); do
    assertContains "$result" "$result" "Set-Cookie: example_prefix_name${i}=${values[i]}; Path=/"
  done
}

test_many_cookies_with_fuzzing_and_shortprefix() {
  local query_params=""
  local values=()

  # ランダムな値を生成して配列に格納
  for i in $(seq 1 100); do
    local len=$((RANDOM % 14 + 1))
    values[i]=$(LC_ALL=C dd bs=512 if=/dev/urandom count=1 | tr -dc 'a-zA-Z0-9' | fold -w $len | head -n 1)
    query_params+="name${i}=${values[i]}&"
  done

  # cURL コマンドの実行
  local result=$(curl -i "http://localhost:1234/a/cookies/set?$query_params")

  # 結果の検証
  for i in $(seq 1 100); do
    assertContains "$result" "$result" "Set-Cookie: aname${i}=${values[i]}; Path=/"
  done
}

. tmp/shunit2/shunit2
