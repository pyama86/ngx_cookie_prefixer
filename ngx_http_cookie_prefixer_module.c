#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

typedef struct {
  ngx_str_t cookie_prefix;
} ngx_http_cookie_prefixer_loc_conf_t;

static char *ngx_http_cookie_prefixer_set_prefix(ngx_conf_t *cf, ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_cookie_prefixer_rewrite_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_cookie_prefixer_header_handler(ngx_http_request_t *r);
static void *ngx_http_cookie_prefixer_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_cookie_prefixer_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child);
static ngx_int_t ngx_http_cookie_prefixer_init(ngx_conf_t *cf);

static ngx_http_output_header_filter_pt ngx_http_next_header_filter;
static ngx_http_module_t ngx_http_cookie_prefixer_module_ctx = {
    NULL,                                     /* preconfiguration */
    ngx_http_cookie_prefixer_init,            /* postconfiguration */
    NULL,                                     /* create main configuration */
    NULL,                                     /* init main configuration */
    NULL,                                     /* create server configuration */
    NULL,                                     /* merge server configuration */
    ngx_http_cookie_prefixer_create_loc_conf, /* create location configuration */
    ngx_http_cookie_prefixer_merge_loc_conf   /* merge location configuration */
};

static ngx_command_t ngx_http_cookie_prefixer_commands[] = {
    {ngx_string("proxy_detach_cookie_prefix"), NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF | NGX_CONF_TAKE1,
     ngx_http_cookie_prefixer_set_prefix, NGX_HTTP_LOC_CONF_OFFSET,
     offsetof(ngx_http_cookie_prefixer_loc_conf_t, cookie_prefix), NULL},
    ngx_null_command};

ngx_module_t ngx_http_cookie_prefixer_module = {NGX_MODULE_V1,
                                                &ngx_http_cookie_prefixer_module_ctx, /* module context */
                                                ngx_http_cookie_prefixer_commands,    /* module directives */
                                                NGX_HTTP_MODULE,                      /* module type */
                                                NULL,                                 /* init master */
                                                NULL,                                 /* init module */
                                                NULL,                                 /* init process */
                                                NULL,                                 /* init thread */
                                                NULL,                                 /* exit thread */
                                                NULL,                                 /* exit process */
                                                NULL,                                 /* exit master */
                                                NGX_MODULE_V1_PADDING};

static char *ngx_http_cookie_prefixer_set_prefix(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
  ngx_http_cookie_prefixer_loc_conf_t *cplcf = conf;
  ngx_str_t *value;

  value                = cf->args->elts;
  cplcf->cookie_prefix = value[1];
  return NGX_CONF_OK;
}

static void *ngx_http_cookie_prefixer_create_loc_conf(ngx_conf_t *cf)
{
  ngx_http_cookie_prefixer_loc_conf_t *conf;

  conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_cookie_prefixer_loc_conf_t));
  if (conf == NULL) {
    return NULL;
  }

  conf->cookie_prefix.data = NULL;
  conf->cookie_prefix.len  = 0;

  return conf;
}

static char *ngx_http_cookie_prefixer_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
  ngx_http_cookie_prefixer_loc_conf_t *prev = parent;
  ngx_http_cookie_prefixer_loc_conf_t *conf = child;

  ngx_conf_merge_str_value(conf->cookie_prefix, prev->cookie_prefix, "");

  return NGX_CONF_OK;
}

static ngx_int_t ngx_http_cookie_prefixer_rewrite_handler(ngx_http_request_t *r)
{
  ngx_http_cookie_prefixer_loc_conf_t *cplcf;
  ngx_str_t *prefix;
  ngx_list_part_t *part;
  ngx_table_elt_t *header;
  ngx_uint_t i;

  cplcf  = ngx_http_get_module_loc_conf(r, ngx_http_cookie_prefixer_module);
  prefix = &cplcf->cookie_prefix;

  if (prefix->data == NULL || prefix->len == 0) {
    return NGX_DECLINED;
  }

  part   = &r->headers_in.headers.part;
  header = part->elts;

  for (i = 0; /* void */; i++) {
    if (i >= part->nelts) {
      if (part->next == NULL) {
        break;
      }

      part   = part->next;
      header = part->elts;
      i      = 0;
    }
    ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "%s:%d: cookie key: %s ", __func__, __LINE__,
                  header[i].key.data);
    if (ngx_strncasecmp(header[i].key.data, (u_char *)"Cookie", 6) == 0) {
      ngx_str_t cookie_value = header[i].value;
      u_char *start          = cookie_value.data;
      u_char *end            = cookie_value.data + cookie_value.len;
      u_char *pos, *name_pos;

      while (start < end) {
        pos = ngx_strnstr(start, "name=", end - start);
        if (pos == NULL) {
          break;
        }

        name_pos = pos + sizeof("name=") - 1;
        pos      = ngx_strnstr(name_pos, (char *)prefix->data, end - name_pos);

        if (pos != NULL && pos < end) {
          ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "%s:%d: before cookie value: %s ", __func__, __LINE__,
                        header[i].value.data);
          ngx_memmove(pos, pos + prefix->len, end - (pos + prefix->len));
          header[i].value.len -= prefix->len;
          ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "%s:%d: after cookie value: %s ", __func__, __LINE__,
                        header[i].value.data);
        } else if (pos == NULL) {
          pos = name_pos;
        }

        start = ngx_strlchr(pos, end, ';');
        if (start == NULL) {
          break;
        }
        start++;
      }
    }
  }
  return NGX_DECLINED;
}

static ngx_int_t ngx_http_cookie_prefixer_header_handler(ngx_http_request_t *r)
{
  ngx_http_cookie_prefixer_loc_conf_t *cplcf;
  ngx_str_t *prefix;
  ngx_list_part_t *part;
  ngx_table_elt_t *header;
  ngx_uint_t i;

  cplcf  = ngx_http_get_module_loc_conf(r, ngx_http_cookie_prefixer_module);
  prefix = &cplcf->cookie_prefix;
  ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "%s:%d: cookie prefix: %s ", __func__, __LINE__, prefix->data);

  if (prefix->data == NULL || prefix->len == 0) {
    return ngx_http_next_header_filter(r);
  }

  part   = &r->headers_out.headers.part;
  header = part->elts;

  for (i = 0; /* void */; i++) {
    if (i >= part->nelts) {
      if (part->next == NULL) {
        break;
      }

      part   = part->next;
      header = part->elts;
      i      = 0;
    }

    if (ngx_strncasecmp(header[i].key.data, (u_char *)"Set-Cookie", 10) == 0) {
      ngx_log_error(NGX_LOG_DEBUG, r->connection->log, 0, "%s:%d: cookie value: %s ", __func__, __LINE__,
                    header[i].value.data);
      ngx_str_t *new_cookie_value = ngx_palloc(r->pool, sizeof(ngx_str_t));
      if (new_cookie_value == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
      }

      new_cookie_value->len  = prefix->len + header[i].value.len;
      new_cookie_value->data = ngx_pnalloc(r->pool, new_cookie_value->len);
      if (new_cookie_value->data == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
      }

      ngx_memcpy(new_cookie_value->data, prefix->data, prefix->len);
      ngx_memcpy(new_cookie_value->data + prefix->len, header[i].value.data, header[i].value.len);
      header[i].value = *new_cookie_value;
    }
  }
  return ngx_http_next_header_filter(r);
}

static ngx_int_t ngx_http_cookie_prefixer_init(ngx_conf_t *cf)
{
  ngx_http_handler_pt *h;
  ngx_http_core_main_conf_t *cmcf;

  cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);
  h    = ngx_array_push(&cmcf->phases[NGX_HTTP_REWRITE_PHASE].handlers);
  if (h == NULL) {
    return NGX_ERROR;
  }
  *h = ngx_http_cookie_prefixer_rewrite_handler;

  ngx_http_next_header_filter = ngx_http_top_header_filter;
  ngx_http_top_header_filter  = ngx_http_cookie_prefixer_header_handler;
  return NGX_OK;
}

