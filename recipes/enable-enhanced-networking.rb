# Cookbook Name:: mh-opsworks-recipes
# Recipe:: enable-enhanced-networking

::Chef::Recipe.send(:include, MhOpsworksRecipes::RecipeHelpers)

include_recipe "awscli::default"
install_package('dkms')
bucket_name = node.fetch(:shared_asset_bucket_name, 'mh-opsworks-shared-assets')
dkms_version = node.fetch(:ixgbevf_version, "2.16.1")

cookbook_file 'enable_enhanced_networking.sh' do
  path "/usr/local/bin/enable_enhanced_networking.sh"
  owner "root"
  group "root"
  mode "700"
end

execute 'fully enable enhanced networking' do
  # This doesn't do anything if the driver is already the correct version
  command %Q|/usr/local/bin/enable_enhanced_networking.sh "#{dkms_version}" "#{bucket_name}"|
end
