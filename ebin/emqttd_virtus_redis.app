{application, emqttd_virtus_redis,
 [
  {description, "emqttd redis plugin - virtus.sense"},
  {vsn, "2.0"},
  {modules, ['emqttd_acl_redis','emqttd_plugin_redis','emqttd_virtus_redis','emqttd_virtus_redis_app','emqttd_virtus_redis_client','emqttd_virtus_redis_sup']},
  {registered, []},
  {applications, [
                  kernel,
                  stdlib,
                  eredis,
                  ecpool
                 ]},
  {mod, { emqttd_virtus_redis_app, []}},
  {env, []}
 ]}.
