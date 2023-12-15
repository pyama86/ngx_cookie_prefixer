NGINX_VERSION=1.25.3
NGINX_PATH = ./nginx
MODULE_SRC = $(CURDIR)/ngx_http_cookie_prefixer.c

nginx:
	curl -s -L -O http://nginx.org/download/nginx-$(NGINX_VERSION).tar.gz
	tar xzf nginx-$(NGINX_VERSION).tar.gz
	mv nginx-$(NGINX_VERSION) $(NGINX_PATH)
	rm -f nginx-$(NGINX_VERSION).tar.gz


# Nginxのビルド設定を指定するオプション
CONFIGURE_ARGS = --add-module=$(CURDIR) --with-debug

# Nginxとモジュールのビルド
build: $(NGINX_PATH)/Makefile
	$(MAKE) -C $(NGINX_PATH)

# Nginxのconfigureスクリプトを実行
$(NGINX_PATH)/Makefile: nginx
	cd $(NGINX_PATH) && ./configure $(CONFIGURE_ARGS)

# クリーンアップ
clean:
	$(MAKE) -C $(NGINX_PATH) clean


DIST_DIR:=./tmp/dist
SHUNIT_VERSION=2.1.8
testdev:
	mkdir -p $(DIST_DIR)
	test -f $(DIST_DIR)/shunit2.tgz || curl -sL https://github.com/kward/shunit2/archive/refs/tags/v$(SHUNIT_VERSION).tar.gz -o $(DIST_DIR)/shunit2.tgz
	test -d tmp/shunit2 || cd $(DIST_DIR); tar xf shunit2.tgz; cd ../
	test -d tmp/shunit2 || mv $(DIST_DIR)/shunit2-$(SHUNIT_VERSION)/ tmp/shunit2

test: testdev build
	mkdir -p nginx/logs
	bash run_test.sh

run:
	docker rm -f nginx-httpbin | true
	docker run -d -p 127.0.0.1:10080:80  --name nginx-httpbin kennethreitz/httpbin
	cp `pwd`/test/test.conf ./nginx/conf/nginx.conf
	pkill nginx | true
	nginx/objs/nginx -p `pwd`/nginx &
