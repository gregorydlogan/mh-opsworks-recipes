# Cookbook Name:: mh-opsworks-recipes
# Recipe:: update-package-repo

execute 'update package repository' do
  environment 'DEBIAN_FRONTEND' => 'noninteractive'
  command 'apt-get update'
  timeout 180
  retries 5
  retry_delay 15
end
