resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
  }
}

resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = var.observability_namespace
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.7.0"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  values = [
    file("${path.module}/values/kube-prometheus-stack.yaml"),
  ]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}

resource "helm_release" "loki_stack" {
  name       = "loki-stack"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = "2.10.2"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900

  values = [
    file("${path.module}/values/loki-stack.yaml"),
  ]

  depends_on = [
    helm_release.kube_prometheus_stack,
  ]
}
