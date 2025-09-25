module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${local.name}-al2023"
  kubernetes_version = "1.33"

  security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description = "Access from VPC"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [local.vpc_cidr]
    }
  }

  # EKS Addons
  addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        autoScaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 10
        }
        tolerations = [
          {
            key      = "dedicated"
            effect   = "NoSchedule"
            operator = "Equal"
            value    = "system"
          }
        ]
        affinity = {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [
                {
                  matchExpressions = [
                    {
                      key      = "pool"
                      operator = "In"
                      values   = ["system"]
                    }
                  ]
                }
              ]
            }
          }
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = module.iam-assumable-role-ebs-csi-addon.iam_role_arn

      configuration_values = jsonencode({
        controller = {
          tolerations = [
            {
              operator = "Exists"
            }
          ],
          nodeSelector = {
            pool = "system"
          }
        }
      })
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  authentication_mode = "API"

  access_entries = {
    terraform = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/akn"
      type          = "STANDARD"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }

    onelogin-admin = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/OneLogin-AIT-AdministratorAccess"
      type          = "STANDARD"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  eks_managed_node_groups = {
   system = {
      min_size     = 2
      max_size     = 2
      desired_size = 2

      instance_types = ["t3a.medium"]
      labels = {
        pool = "system"
      }

      iam_role_additional_policies = merge(
        {
          AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }
      )

      taints = {
        dedicated = {
          key    = "dedicated"
          value  = "system"
          effect = "NO_SCHEDULE"
        }
      }

      tags = {
        pool = "system"
      }
    }
    worker = {
      min_size     = 2
      max_size     = 4
      desired_size = 4

      instance_types = ["t3a.medium"]
      labels = {
        pool = "worker"
      }

      iam_role_additional_policies = merge(
        {
          AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }
      )

      tags = {
        pool = "worker"
      }
    }
  }

  tags = local.tags
}

################################################################################
# EKS CSI Addon Module
################################################################################

module "iam-assumable-role-ebs-csi-addon" {
  source                         = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                        = "5.39.0"
  create_role                    = true
  provider_url                   = module.eks.oidc_provider
  role_name                      = "${local.name}-ebs-csi-driver-ROLE"
  oidc_fully_qualified_subjects  = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
  oidc_fully_qualified_audiences = ["sts.amazonaws.com"]
  role_policy_arns               = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
}

################################################################################
# GP3 Storage Class
################################################################################

resource "kubernetes_storage_class" "gp3" {

  metadata {
    name = "gp3"
  }

  storage_provisioner = "ebs.csi.aws.com" # Amazon EBS CSI driver

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"
  depends_on          = [module.eks]
}

### SG to work with the EKS ALB ingress controller
resource "aws_security_group" "alb-controller-sg" {
  name        = "cluster-alb-controller-sg"
  description = "SG to work with the EKS ALB ingress controller"
  vpc_id      = module.vpc.vpc_id
}