# prerequisites
- docker desktop
- minikube

# start minikube
```bash
minikube start --cpus 15 --memory 38g
minikube start --cni=calico --cpus 15 --memory 38g
```

# Create argocd
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

# After startup deploy confluent dev environment
```bash
kubectl apply -n argocd -f argocd/root/dev.yaml
```