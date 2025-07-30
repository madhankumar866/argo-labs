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

create_cluster() {
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
}

setup_argocd_access() {
    print_step "Setting up ArgoCD access..."
    
    # Patch ArgoCD server service to NodePort for easy access
    kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":30080,"name":"http"},{"port":443,"targetPort":8080,"nodePort":30443,"name":"https"}]}}'
    
    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
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

setup_demo_apps() {
    print_step "Setting up demo applications..."
    
    # Create demo namespace
    kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
    
    # Create a simple demo application manifest
    cat << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
EOF
    
    print_success "Demo applications configured"
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

main() {
    print_header
    check_prerequisites

    echo "1. Create Kind cluster"
    echo "2. Install ArgoCD"
    echo "3. Setup ArgoCD access"
    echo "4. Install ArgoCD CLI"
    echo "5. Setup demo apps"
    echo "6. Get ArgoCD login information"
    echo "7. Run when you're done to clean up resources"
    read -p "Enter your choice: " choice

    case $choice in
        1)
            create_cluster
            ;;
        2)
            install_argocd
            ;;
        3)
            setup_argocd_access
            ;;
        4) 
            install_argocd_cli
            ;;
        5)
            setup_demo_apps
            ;;
        6)  
            getargocdlogin
            ;;
        7)
            cleanup
            ;;  
        8)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Exiting..."
            exit 1
            ;;
    esac
}
# Run main function
main "$@"