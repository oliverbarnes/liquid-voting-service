k8s_yaml([
  'k8s/nginx-ingress-load-balancer.yaml',
  'k8s/ingress.yaml',
  'k8s/database-persistent-volume-claim.yaml',
  'k8s/database-service.yaml',
  'k8s/database-deployment.yaml',
  'k8s/liquid-voting-service.yaml',
  'k8s/liquid-voting-deployment.yaml',
  'k8s/monitoring/namespace.yaml',
  'k8s/monitoring/grafana/config.yaml'
])

docker_build('oliverbarnes/liquid-voting-service', '.')