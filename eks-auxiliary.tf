provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_eks_cluster_auth" "this" {
  name = "${local.name}-al2023"
}

module "eks-aux" {

  source = "github.com/automat-it/terraform-aws-eks-auxiliary.git?ref=v1.33.1"

  # Components
  services = {
    argocd = {
      enabled  = true
      nodepool = ""
      version  = "7.3.7"
    }
    aws-alb-ingress-controller = {
      enabled                = true
      additional_helm_values = <<-EOF
      backendSecurityGroup: "${aws_security_group.alb-controller-sg.id}"
      EOF
    }
    cluster-autoscaler = {
      enabled = false
    }
    external-dns = {
      enabled = true
    }
    external-secrets = {
      enabled = true
    }
    metrics-server = {
      enabled = true
    }
  }

  # AWS
  aws_region = local.region
  account_id = data.aws_caller_identity.current.account_id

  # EKS
  cluster_name        = module.eks.cluster_name
  cluster_endpoint    = module.eks.cluster_endpoint
  iam_openid_provider = {
    oidc_provider_arn = module.eks.oidc_provider_arn
    oidc_provider     = module.eks.oidc_provider
  }

  # VPC
  vpc_id = module.vpc.vpc_id

  # DNS
  r53_zone_id = "Z04468782VEJE996QSB6N"
  domain_zone = "aws.lockirin.pp.ua"

  # Tags
  tags = {
    Managed_by  = "Terraform"
    Environment = "Development"
  }
}