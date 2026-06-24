locals {
  # flatten ensures that this local value is a flat list of objects, rather
  # than a list of lists of objects.
  project_environments = flatten([
    for project, proj_settings in var.projects : [
      for env_id, env in proj_settings.environments : {
        project          = project
        env              = env
        namespace        = proj_settings.single_namespace ? join("-", compact([project, env])) : join("-", compact([project, env, "{{path.basename}}"]))
        serverside_apply = proj_settings.serverside_apply

      }
    ]
  ])
  argocd_token_name    = join("-", compact([var.subgroup_name_token_prefix, var.subgroup_name, "argocd"]))
  default_sync_options = ["CreateNamespace=true", "RespectIgnoreDifferences=false"]
}
