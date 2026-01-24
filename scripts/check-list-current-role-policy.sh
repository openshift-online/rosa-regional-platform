#!/bin/bash

aws iam list-roles --no-paginate --no-cli-pager --query 'sort_by(Roles, &CreateDate)[].{RoleName: RoleName, CreateDate: CreateDate}' --output table | tail -n 20
aws iam list-policies --no-paginate --no-cli-pager --query 'sort_by(Policies, &CreateDate)[].{PolicyName: PolicyName, CreateDate: CreateDate}' --output table | tail -n 20