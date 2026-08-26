# Remote state backend for the dev environment.
# Bucket/table provisioned once via scripts/bootstrap-state.sh (PETPLAT-2).
terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-228870477355"
    key            = "petclinic/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
