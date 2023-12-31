# ngx_cookie_prefixer
Detach and attach the prefix of nginx cookies with this module."

## usage
```
worker_processes  1;
load_module ngx_http_cookie_prefixer_module.so;
events {
    worker_connections  200;
}

daemon off;
master_process off;
error_log logs/error.log debug;
http {
    include       mime.types;
    server {
        listen       127.0.0.1:1234;
        server_name  localhost;
        location /{
          # support location and server
          proxy_detach_cookie_prefix example_prefix_;
          proxy_pass http://localhost:10080;
        }
    }
}
```

## test
```
$ make test
```

## author
- @pyama86
