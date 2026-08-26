# Remote state backend for the prod environment.
# Same bucket/table as dev (PETPLAT-2), different state key.
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-228870477355"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
