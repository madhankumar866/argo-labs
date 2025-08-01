
#!/bin/bash

# ArgoCD Lab Environment Startup Script
# This script creates a Kind cluster and sets up ArgoCD for exam preparation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="argocd-lab"
# ARGOCD_VERSION="v2.12.3"
ARGOCD_VERSION="stable" # Use 'stable' to always get the latest stable version
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  ArgoCD Lab Environment Setup  ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
}

print_step() {
    echo -e "${YELLOW}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Install NGINX Ingress Controller for Kind
install_kind_ingress() {
    print_step "Installing NGINX Ingress Controller for Kind..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/kind/deploy.yaml
    print_success "NGINX Ingress Controller installed."
}

# Label node(s) as ingress-ready for Ingress controller scheduling
label_ingress_node() {
    print_step "Labeling node(s) as ingress-ready..."
    # For Kind, label all nodes named 'argocd-lab-control-plane' or similar
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        for node in $(kubectl get nodes -o name | sed 's|node/||'); do
            kubectl label node "$node" ingress-ready=true --overwrite
            echo "Labeled $node as ingress-ready=true"
        done
    # For Minikube, label all nodes in the 'argo' profile
    elif minikube profile list | grep -q '^| argo-lab '; then
        for node in $(kubectl get nodes -o name | sed 's|node/||'); do
            kubectl label node "$node" ingress-ready=true --overwrite
            echo "Labeled $node as ingress-ready=true"
        done
    else
        print_error "No recognized cluster found for labeling."
    fi
    print_success "Node labeling complete."
}

# minikube addons enable ingress -p argo
install_minikube_ingress() {
    print_step "Enabling Ingress addon for Minikube..."
    minikube addons enable ingress -p argo-lab
    minikube addons enable ingress-dns -p argo-lab
    if [ $? -ne 0 ]; then
        print_error "Failed to enable Ingress addon. Please check the logs."
        exit 1
    fi
    print_success "Ingress addon enabled for Minikube profile 'argo'."
}
# Create a single Ingress for ArgoCD and Argo Workflows
create_argocd_and_workflows_ingress() {
    print_step "Creating a single Ingress for ArgoCD and Argo Workflows..."
    # Patch services to ClusterIP
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "ClusterIP"}}' || true
    kubectl patch svc argo-server -n argo -p '{"spec": {"type": "ClusterIP"}}' || true

    # Combined Ingress
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argo-cd-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argo-workflow-ingress
  namespace: argo
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:              
  - host: argo.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argo-server
            port:
              number: 2746
EOF

    print_success "Single Ingress for ArgoCD (argocd.local) and Argo Workflows (argo.local) created."
    echo "Add the following to your /etc/hosts file:"
    echo "127.0.0.1 argocd.local argo.local"
    echo "Access ArgoCD UI at https://argocd.local and Argo Workflows UI at http://argo.local:2746 or http://argo.local"
}

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check if kind is installed
    if ! command -v kind &> /dev/null; then
        print_error "Kind is not installed. Please install it first:"
        echo "  macOS: brew install kind"
        echo "  Linux: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first:"
        echo "  macOS: brew install kubectl"
        echo "  Linux: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker Desktop or Docker daemon."
        exit 1
    fi
    
    print_success "All prerequisites are satisfied"
}

create_kind_cluster() {
    print_step "Creating Kind cluster '$CLUSTER_NAME'..."
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo "Cluster '$CLUSTER_NAME' already exists. Deleting it first..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    # Create the cluster
    kind create cluster --config "$SCRIPT_DIR/cluster-config.yaml" --wait 300s
    
    # Wait for all nodes to be ready
    echo "Waiting for all nodes to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    print_success "Kind cluster created successfully"
    
    # Display cluster info
    echo
    echo "Cluster Information:"
    kubectl get nodes -o wide

    # Label nodes for ingress
    # label_ingress_node
}

# Create a Minikube cluster with profile 'argo' and 2 nodes
create_minikube_cluster() {
    print_step "Creating Minikube cluster with profile 'argo' and 2 nodes..."
    minikube start -p argo-lab --nodes 3 --driver=docker --cpus 3 --memory 3024 --disk-size 15g
    if [ $? -ne 0 ]; then
        print_error "Failed to create Minikube cluster. Please check the logs."
        exit 1
    fi
    print_success "Minikube cluster 'argo-lab' with 2 nodes created successfully."
    echo
    minikube status -p argo-lab
    echo "viewing all profiles."
    minikube profile list
    echo "### To start a cluster, run: minikube start -p argo"

    # Label nodes for ingress
    label_ingress_node
}


install_argocd() {
    print_step "Installing ArgoCD..."
    
    # Create argocd namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD
    kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"
    if [ $? -ne 0 ]; then
        print_error "Failed to install ArgoCD. Please check the logs."
        exit 1
    fi
    # Wait for ArgoCD to be ready
    echo "Waiting for ArgoCD components to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-dex-server -n argocd
    
    print_success "ArgoCD installed successfully"

    print_step "Setting up ArgoCD access..."
    
    # Patch ArgoCD server service to NodePort for easy access
    # kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":30080,"name":"http"},{"port":443,"targetPort":8080,"nodePort":30443,"name":"https"}]}}'

    # Argocd patch for ingress to allow insecure connections
    kubectl -n argocd patch deployment argocd-server \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'
        
    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    kubectl -n argocd rollout restart deployment argocd-server
    print_success "ArgoCD access configured"
    
    echo
    echo "============================================"
    echo "ArgoCD Access Information:"
    echo "============================================"
    echo "URL: http://localhost:30080"
    echo "Username: admin"
    echo "Password: $ARGOCD_PASSWORD"
    echo
    echo "Alternative access via port-forward:"
    echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "Then access: https://localhost:8080"
    echo "============================================"
}
install_argo_workflows() {


    ARGO_WORKFLOWS_VERSION="v3.7.0" # Specify the version you want to install
    print_step "Installing Argo Workflows version $ARGO_WORKFLOWS_VERSION..."
    # Create argo namespace
    kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
    # Install Argo Workflows
    kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/$ARGO_WORKFLOWS_VERSION/install.yaml
    if [ $? -ne 0 ]; then
        print_error "Failed to install Argo Workflows. Please check the logs."
        exit 1
    fi
    # Wait for Argo Workflows controller to be ready
    echo "####Waiting for Argo Workflows controller to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argo-server -n argo
    print_success "Argo Workflows installed successfully"

    echo "####Changing the authentication mode to Server Authentication."
    kubectl patch deployment \
    argo-server \
    --namespace argo \
    --type='json' \
    -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["server","--auth-mode=server"]}]'
    
    echo "####Argo Workflows server is now running with auth-mode set to 'server'."
    if ! kubectl get rolebinding argo-default-admin -n argo &> /dev/null; then
        kubectl create rolebinding argo-default-admin --clusterrole=admin --serviceaccount=argo:default -n argo
        echo "####Role-Based Access Control (RBAC) to grant Argo Admin-level permissions "
    else
        echo "####RoleBinding 'argo-default-admin' already exists. Skipping creation."
    fi
    
    # Expose via Ingress
    # install_kind_ingress
    # create_argo_ingress
}



install_argocd_cli() {
    print_step "Installing ArgoCD CLI..."
    
    # Check if argocd CLI is already installed
    if command -v argocd &> /dev/null; then
        echo "ArgoCD CLI is already installed: $(argocd version --client --short)"
        return
    fi
    
    # Install ArgoCD CLI based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install argocd
        else
            echo "Installing ArgoCD CLI manually..."
            curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-darwin-amd64
            chmod +x argocd
            sudo mv argocd /usr/local/bin/
        fi
    else
        # Linux
        echo "Installing ArgoCD CLI for Linux..."
        curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        chmod +x argocd
        sudo mv argocd /usr/local/bin/
    fi
    
    print_success "ArgoCD CLI installed successfully"
}


    
getargocdlogin() {
    echo "=== Cluster Status ==="
    kubectl get nodes

    echo -e "\n=== ArgoCD Pods ==="
    kubectl get pods -n argocd

    echo -e "\n=== ArgoCD Applications ==="
    kubectl get applications -n argocd

    echo -e "\n=== ArgoCD Access Info ==="
    echo "URL: http://localhost:30080"
    echo "Username: admin"
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
    if [ -n "$ARGOCD_PASSWORD" ]; then
        echo "Password: $ARGOCD_PASSWORD"
    else
        echo "Password: (secret not found - ArgoCD may not be fully ready)"
    fi
}

cleanup() {
    CLUSTER_NAME="argocd-lab"

    echo "Deleting Kind cluster '$CLUSTER_NAME'..."
    kind delete cluster --name "$CLUSTER_NAME"

    echo "Cleanup completed!"
}
minikubecleanup() {
    projectname="argo-lab"
    echo "Deleting Kind cluster '$projectname'..."
    minikube delete --profile $projectname
    echo "Cleanup completed!"
    # kill -9 $(ps aux | grep "minikube tunnel" | awk '{print $2}') 2>/dev/null || true
    # echo "Tunnel process killed if it was running."
}
minikubetunnel() {
    projectname="argo-lab"
    echo "Tunneling Minikube cluster '$projectname'..."
    minikube tunnel --profile $projectname
    echo "Tunnel started. Press Ctrl+C to stop."
    curl -k --resolve "argo.local:443:127.0.0.1" https://argo.local
}
main() {
    print_header
    check_prerequisites

    echo "1. Create Kind cluster"
    echo "2. Create Minikube cluster"
    echo "3. Install ArgoCD"
    echo "4. Install Argo Workflows"
    echo "5. Install ArgoCD CLI"
    echo "6. Get ArgoCD login information"
    echo "8. Kind Run when you're done to clean up resources"
    echo "9. Minikube Run when you're done to clean up resources"
    echo "9. ingress multi step"
    echo "12. create_argocd_and_workflows_ingress"

    read -p "Enter your choice: " choice

    case $choice in
        1)
            create_kind_cluster
            ;;
        2)            
            create_minikube_cluster
            ;;            
        3)
            install_argocd
            ;;
        4)
            install_argo_workflows
            ;;
        5) 
            install_argocd_cli
            ;;
        6)  
            getargocdlogin
            ;;
        8)
            cleanup
            ;;
        9)
            label_ingress_node
            install_kind_ingress
            ;;
        11)
            minikubecleanup
            ;;
        12)
            create_argocd_and_workflows_ingress
            ;;
        13) install_minikube_ingress
            minikubetunnel
            ;;            
        *)
            echo "Invalid choice. Exiting..."
            exit 1
            ;;
    esac
}
# Run main function
main "$@"