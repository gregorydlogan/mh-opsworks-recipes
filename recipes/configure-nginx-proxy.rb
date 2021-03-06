# Cookbook Name:: mh-opsworks-recipes
# Recipe:: configure-nginx-proxy

include_recipe "mh-opsworks-recipes::update-package-repo"
::Chef::Recipe.send(:include, MhOpsworksRecipes::RecipeHelpers)
install_package('nginx')

install_nginx_logrotate_customizations

template %Q|/etc/nginx/sites-enabled/default| do
  source 'nginx-proxy.conf.erb'
  manage_symlink_source true
  variables({
    matterhorn_backend_http_port: 8080
  })
end

directory '/etc/nginx/proxy-includes' do
  owner 'root'
  group 'root'
end

execute 'service nginx reload'
