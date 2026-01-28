output "accounts" {
  value = {
    for k, v in aws_organizations_account.account : k => {
      id     = v.id
      arn    = v.arn
      name   = v.name
      region = local.regions[k].region
      type   = local.regions[k].type
    }
  }
}
