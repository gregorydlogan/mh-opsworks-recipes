require 'uri'
module MhOpsworksRecipes
  module RecipeHelpers

    def get_memory_limit
      # Default opsworks tuning gives mysql most of the instance memory, as it should
      if database_node?
        95
      else
        80
      end
    end

    def install_package(name)
      #
      # Yes, I know about the "package" resource, but for some reason using a timeout
      # with it causes a compile-time error.
      #
      # We really want to be able to timeout and retry installs to get faster package
      # mirrors. This is an annoying quirk with the ubuntu package mirror repos.
      #
      execute "install #{name}" do
        environment 'DEBIAN_FRONTEND' => 'noninteractive'
        command %Q|apt-get install -y #{name}|
        retries 5
        retry_delay 15
        timeout 180
      end
    end

    def get_shared_asset_bucket_name
      node.fetch(:shared_asset_bucket_name, 'mh-opsworks-shared-assets')
    end

    def get_seed_file
      node.fetch(:cluster_seed_file, 'cluster_seed.tgz')
    end

    def testing_cluster?
      ['development', 'test'].include?(node[:cluster_env])
    end

    def database_node?
      node['opsworks']['instance']['hostname'].match(/^db-master/)
    end

    def engage_node?
      node['opsworks']['instance']['hostname'].match(/^engage/)
    end

    def admin_node?
      node['opsworks']['instance']['hostname'].match(/^admin/)
    end

    def get_db_seed_file
      node.fetch(:db_seed_file, 'dce-config/docs/scripts/ddl/mysql5.sql')
    end

    def get_deploy_action
      valid_actions = %i|deploy force_deploy rollback|
      requested_action = node.fetch(:deploy_action, :deploy).to_sym
      Chef::Log.info "requested_action: #{requested_action}"
      if valid_actions.include?(requested_action)
        requested_action
      else
        :deploy
      end
    end

    def get_live_stream_name
      node.fetch(:live_stream_name, '#{caName}-#{flavor}.stream-#{resolution}_1_200@')
    end

    def get_live_streaming_url
      node.fetch(:live_streaming_url, 'rtmp://example.com/streaming_url')
    end

    def get_public_engage_hostname_on_engage
      return node[:public_engage_hostname] if node[:public_engage_hostname]

      node[:opsworks][:instance][:public_dns_name]
    end

    def get_public_admin_hostname_on_admin
      return node[:public_admin_hostname] if node[:public_admin_hostname]

      node[:opsworks][:instance][:public_dns_name]
    end

    def get_public_admin_hostname
      return node[:public_admin_hostname] if node[:public_admin_hostname]

      (private_admin_hostname, admin_attributes) = node[:opsworks][:layers][:admin][:instances].first

      admin_hostname = ''
      if admin_attributes
        admin_hostname = admin_attributes[:public_dns_name]
      end
      admin_hostname
    end

    def using_asset_server?
      node[:opsworks][:layers][:asset_server] && node[:opsworks][:layers][:asset_server][:instances].any?
    end

    def using_ssl_for_engage?
      node[:ssl]
    end

    def get_base_media_download_domain(engage_hostname)
      uri = URI(get_base_media_download_url(engage_hostname))
      uri.host
    end

    def get_base_media_download_url(engage_hostname)
      # engage_hostname is passed in because we don't have the engage instance
      # chef attributes when we're deploying the engage instance. The chef
      # attributes don't make it into the shared chef environment until the
      # node comes online.

      cloudfront_url = get_cloudfront_url
      base_media_download_url = ''

      if cloudfront_url && (! cloudfront_url.empty?)
        Chef::Log.info "Cloudfront url: #{cloudfront_url}"
        base_media_download_url = %Q|https://#{cloudfront_url}|
      elsif using_asset_server?
        Chef::Log.info "asset server url: #{get_public_asset_server_hostname}"
        base_media_download_url = %Q|http://#{get_public_asset_server_hostname}/static|
      else
        Chef::Log.info "engage server: #{engage_hostname}"
        protocol = (using_ssl_for_engage?) ? 'https://' : 'http://'
        base_media_download_url = %Q|#{protocol}#{engage_hostname}/static|
      end
      base_media_download_url
    end

    def get_public_asset_server_hostname
      if using_asset_server?
        (private_asset_server_hostname, asset_server_attributes) = node[:opsworks][:layers][:asset_server][:instances].first
        return asset_server_attributes[:public_dns_name]
      end
    end

    def get_public_engage_hostname
      return node[:public_engage_hostname] if node[:public_engage_hostname]

      (private_engage_hostname, engage_attributes) = node[:opsworks][:layers][:engage][:instances].first

      public_engage_hostname = ''
      if engage_attributes
        public_engage_hostname = engage_attributes[:public_dns_name]
      end
      public_engage_hostname
    end

    def get_public_engage_ip
      (private_engage_hostname, engage_attributes) = node[:opsworks][:layers][:engage][:instances].first
      engage_attributes[:ip]
    end

    def get_public_admin_ip
      (private_admin_hostname, admin_attributes) = node[:opsworks][:layers][:admin][:instances].first
      admin_attributes[:ip]
    end

    def get_cloudfront_url
      node[:cloudfront_url]
    end

    def get_admin_user_info
      node.fetch(
        :admin_auth, {
          user: 'admin',
          pass: 'password'
        }
      )
    end

    def topic_name
      stack_name = node[:opsworks][:stack][:name]
      stack_name.downcase.gsub(/[^a-z\d\-_]/,'_')
    end

    def alarm_name_prefix
      hostname = node[:opsworks][:instance][:hostname]
      alarm_name_prefix = %Q|#{topic_name}_#{hostname}|
    end

    def short_stack_name
      topic_name
    end

    def stack_and_hostname
      alarm_name_prefix
    end

    def toggle_maintenance_mode_to(mode)
      rest_auth_info = get_rest_auth_info
      (private_admin_hostname, admin_attributes) = node[:opsworks][:layers][:admin][:instances].first
      hostname = ''

      hostname = node[:opsworks][:instance][:private_dns_name]

      if private_admin_hostname
        command = %Q|/usr/bin/curl -s --digest -u "#{rest_auth_info[:user]}:#{rest_auth_info[:pass]}" -H "X-Requested-Auth: Digest" -F host=http://#{hostname} -F maintenance=#{mode} http://#{private_admin_hostname}/services/maintenance|
        # Chef::Log.info "command: #{command}"
        execute "toggle maintenance mode to #{mode}" do
          user 'matterhorn'
          command command
          retries 5
          retry_delay 30
        end
      end
    end

    def get_rest_auth_info
      node.fetch(
        :rest_auth, {
          user: 'user',
          pass: 'pass'
        }
      )
    end

    def get_storage_info
      node.fetch(
        :storage, {
          shared_storage_root: '/var/tmp',
          export_root: '/var/tmp',
          network: '10.0.0.0/8',
          layer_shortname: 'storage'
        }
      )
    end

    def get_shared_storage_root
      storage_info = get_storage_info
      storage_info[:shared_storage_root] || storage_info[:export_root]
    end

    def get_local_workspace_root
      node.fetch(
        :local_workspace_root, '/var/matterhorn-workspace'
      )
    end

    def get_log_directory
      node.fetch(
        :matterhorn_log_directory, '/var/log/matterhorn'
      )
    end

    def allow_matterhorn_user_to_restart_daemon_via_sudo
      file '/etc/sudoers.d/matterhorn' do
        owner 'root'
        group 'root'
        content %Q|matterhorn ALL=NOPASSWD:/etc/init.d/matterhorn\n|
        mode '0600'
      end
    end

    def git_repo_url(git_data)
      git_user = git_data[:user]

      repo = ''
      if git_user
        # Using a repo in the form of "https://user:pass@repo_url"
        user = git_data[:user]
        password = git_data[:password]
        repo = git_data[:repository]
        fixed_repo = repo.gsub(/\Ahttps?:\/\//,'')
        repo = %Q|https://#{user}:#{password}@#{fixed_repo}|
      else
        # Using a repo with an SSH key, or with no auth
        repo = git_data[:repository]
      end
      repo
    end
  end

  module DeployHelpers
    def files_for(node_profile)
      files = {
        admin: [
          {
            src: 'dce-config/email/errorDetails',
            dest: 'etc/email/errorDetails'
          },
          {
            src: 'dce-config/email/eventDetails',
            dest: 'etc/email/eventDetails'
          },
          {
            src: 'dce-config/email/metasynchDetails',
            dest: 'etc/email/metasynchDetails'
          },
          {
            src: 'dce-config/services/org.ops4j.pax.logging.properties',
            dest: 'etc/services/org.ops4j.pax.logging.properties'
          },
        ],
        worker: [
          {
            src: 'dce-config/email/errorDetails',
            dest: 'etc/email/errorDetails'
          },
          {
            src: 'dce-config/email/eventDetails',
            dest: 'etc/email/eventDetails'
          },
          {
            src: 'dce-config/email/metasynchDetails',
            dest: 'etc/email/metasynchDetails'
          },
          {
            src: 'dce-config/encoding/DCE-h264-movies.properties',
            dest: 'etc/encoding/DCE-h264-movies.properties'
          },
          {
            src: 'dce-config/workflows/DCE-error-handler.xml',
            dest: 'etc/workflows/DCE-error-handler.xml',
          },
          {
            src: 'dce-config/services/org.ops4j.pax.logging.properties',
            dest: 'etc/services/org.ops4j.pax.logging.properties'
          },
        ],
        engage: [
          {
            src: 'dce-config/email/errorDetails',
            dest: 'etc/email/errorDetails'
          },
          {
            src: 'dce-config/email/eventDetails',
            dest: 'etc/email/eventDetails'
          },
          {
            src: 'dce-config/email/metasynchDetails',
            dest: 'etc/email/metasynchDetails'
          },
          {
            src: 'dce-config/workflows/DCE-error-handler.xml',
            dest: 'etc/workflows/DCE-error-handler.xml',
          },
          {
            src: 'dce-config/services/org.ops4j.pax.logging.properties',
            dest: 'etc/services/org.ops4j.pax.logging.properties'
          },
        ]
      }
      files.fetch(node_profile.to_sym, [])
    end

    def install_published_event_details_email(current_deploy_root, engage_hostname)
      template %Q|#{current_deploy_root}/etc/email/publishedEventDetails| do
        source 'publishedEventDetails.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          engage_hostname: engage_hostname
        })
      end
    end

    def configure_usertracking(current_deploy_root, user_tracking_authhost)
      template %Q|#{current_deploy_root}/etc/services/org.opencastproject.usertracking.impl.UserTrackingServiceImpl.properties| do
        source 'UserTrackingServiceImpl.properties.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          user_tracking_authhost: user_tracking_authhost
        })
      end
    end

    def install_otherpubs_service_config(current_deploy_root, auth_host)
      template %Q|#{current_deploy_root}/etc/services/edu.harvard.dce.otherpubs.service.OtherpubsService.properties| do
        source 'edu.harvard.dce.otherpubs.service.OtherpubsService.properties.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          auth_host: auth_host
        })
      end
    end

    def set_service_registry_dispatch_interval(current_deploy_root)
      template %Q|#{current_deploy_root}/etc/services/org.opencastproject.serviceregistry.impl.ServiceRegistryJpaImpl.properties| do
        source 'ServiceRegistryJpaImpl.properties.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          dispatch_interval: 0
        })
      end
    end

    def install_matterhorn_images_properties(current_deploy_root)
      template %Q|#{current_deploy_root}/etc/encoding/matterhorn-images.properties| do
        source 'matterhorn-images.properties.erb'
        owner 'matterhorn'
        group 'matterhorn'
      end
    end

    def install_matterhorn_log_management
      compress_after_days = 7
      delete_after_days = 180
      log_dir = node.fetch(:matterhorn_log_directory, '/var/log/matterhorn')

      cron_d 'compress_matterhorn_logs' do
        user 'matterhorn'
        predefined_value '@daily'
        command %Q(find #{log_dir} -maxdepth 1 -type f -name 'matterhorn.log.2*' -not -name '*.gz' -mtime +#{compress_after_days} -exec /bin/gzip {} \\;)
        path '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
      end

      cron_d 'delete_matterhorn_logs' do
        user 'matterhorn'
        predefined_value '@daily'
        command %Q(find #{log_dir} -maxdepth 1 -type f -name 'matterhorn.log.2*.gz' -mtime +#{delete_after_days} -delete)
        path '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
      end
    end

    def install_init_scripts(current_deploy_root, matterhorn_repo_root)
      log_dir = node.fetch(:matterhorn_log_directory, '/var/log/matterhorn')

      auto_configure_java_xmx_memory = node.fetch(:auto_configure_java_xmx_memory, false)
      java_xmx_ram = 4096
      if auto_configure_java_xmx_memory
        total_ram_in_meg = %x(grep MemTotal /proc/meminfo | sed -r 's/[^0-9]//g').chomp.to_i / 1024
        # A third of the RAM, minimum of 4096M for the java daemon
        java_xmx_ram = [total_ram_in_meg / 3, 4096].max
      end

      template %Q|/etc/init.d/matterhorn| do
        source 'matterhorn-init-script.erb'
        owner 'matterhorn'
        group 'matterhorn'
        mode '755'
        variables({
          matterhorn_executable: matterhorn_repo_root + '/current/bin/matterhorn'
        })
      end

      template %Q|#{current_deploy_root}/bin/matterhorn| do
        source 'matterhorn-harness.erb'
        owner 'matterhorn'
        group 'matterhorn'
        mode '755'
        variables({
          java_xmx_ram: java_xmx_ram,
          main_config_file: %Q|#{matterhorn_repo_root}/current/etc/matterhorn.conf|,
          matterhorn_root: matterhorn_repo_root + '/current',
          felix_config_dir: matterhorn_repo_root + '/current/etc',
          matterhorn_log_directory: log_dir
        })
      end
    end

    def install_matterhorn_conf(current_deploy_root, matterhorn_repo_root, node_profile)
      log_dir = node.fetch(:matterhorn_log_directory, '/var/log/matterhorn')

      template %Q|#{current_deploy_root}/etc/matterhorn.conf| do
        source 'matterhorn.conf.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          matterhorn_root: matterhorn_repo_root + '/current',
          node_profile: node_profile,
          matterhorn_log_directory: log_dir
        })
      end
    end

    def install_multitenancy_config(current_deploy_root, admin_hostname, engage_hostname)
      template %Q|#{current_deploy_root}/etc/load/org.opencastproject.organization-mh_default_org.cfg| do
        source 'mh_default_org.cfg.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          hostname: admin_hostname,
          admin_hostname: admin_hostname,
          engage_hostname: engage_hostname
        })
      end
    end

    def install_smtp_config(current_deploy_root)
      smtp_auth = node.fetch(:smtp_auth, {})
      default_email_sender = smtp_auth.fetch(:default_email_sender, 'no-reply@localhost')

      template %Q|#{current_deploy_root}/etc/services/org.opencastproject.kernel.mail.SmtpService.properties| do
        source 'org.opencastproject.kernel.mail.SmtpService.properties.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          default_email_sender: default_email_sender,
        })
      end
    end

    def install_live_streaming_service_config(current_deploy_root,live_stream_name)
      template %Q|#{current_deploy_root}/etc/services/edu.harvard.dce.live.impl.LiveServiceImpl.properties| do
        source 'edu.harvard.dce.live.impl.LiveServiceImpl.properties.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          live_stream_name: live_stream_name
        })
      end
    end

    def install_auth_service(current_deploy_root, auth_host, redirect_location, auth_activated = 'true')
      template %Q|#{current_deploy_root}/etc/services/edu.harvard.dce.auth.impl.HarvardDCEAuthServiceImpl.properties| do
        source 'edu.harvard.dce.auth.impl.HarvardDCEAuthServiceImpl.properties.erb'
        owner 'matterhorn'
        group 'matterhorn'
        variables({
          auth_host: auth_host,
          redirect_location: redirect_location,
          auth_activated: auth_activated
        })
      end
    end

    def copy_workflows_into_place_for_admin(current_deploy_root)
      execute 'copy workflows into place for admin' do
        command %Q|find #{current_deploy_root}/dce-config/workflows -maxdepth 1 -type f -exec cp -t #{current_deploy_root}/etc/workflows {} +|
        retries 3
        retry_delay 10
      end
    end

    def copy_configs_for_load_service(current_deploy_root)
      execute 'copy service configs' do
        command %Q|find #{current_deploy_root}/dce-config/load -maxdepth 1 -type f -exec cp -t #{current_deploy_root}/etc/load {} +|
        retries 3
        retry_delay 10
      end
    end

    def copy_services_into_place(current_deploy_root)
      execute 'copy services' do
        command %Q|find #{current_deploy_root}/dce-config/services -maxdepth 1 -type f -exec cp -t #{current_deploy_root}/etc/services {} +|
        retries 3
        retry_delay 10
      end
    end

    def copy_files_into_place_for(node_profile, current_deploy_root)
      files_for(node_profile).each do |file_config|
        source_file = %Q|#{current_deploy_root}/#{file_config[:src]}|
        destination_file = %Q|#{current_deploy_root}/#{file_config[:dest]}|
        file destination_file do
          owner 'matterhorn'
          group 'matterhorn'
          mode '644'
          content lazy { ::File.read(source_file) }
          action :create
        end
      end
    end

    def maven_build_for(node_profile, current_deploy_root)
      # TODO - if failed builds continue to be an issue because of ephemeral
      # node_modules or issues while maven pulls down artifacts,
      # run this in a begin/rescue block and retry a build immediately
      # after failure a few times before permanently failing
      build_profiles = {
        admin: 'admin,dist-stub,engage-stub,worker-stub,workspace,serviceregistry',
        ingest: 'ingest-standalone',
        worker: 'worker-standalone,serviceregistry,workspace',
        engage: 'engage-standalone,dist,serviceregistry,workspace'
      }
      execute 'maven build for matterhorn' do
        command %Q|cd #{current_deploy_root} && MAVEN_OPTS='-Xms256m -Xmx960m -XX:PermSize=64m -XX:MaxPermSize=256m' mvn clean install -DdeployTo="#{current_deploy_root}" -Dmaven.test.skip=true -P#{build_profiles[node_profile.to_sym]}|
        retries 3
        retry_delay 30
      end
    end

    def remove_felix_fileinstall(current_deploy_root)
      file %Q|#{current_deploy_root}/etc/load/org.apache.felix.fileinstall-matterhorn.cfg| do
        action :delete
      end
    end

    def path_to_most_recent_deploy(resource)
      deploy_root = resource.deploy_to + '/releases/'
      all_entries = Dir.new(deploy_root).entries
      deploy_directories = all_entries.find_all do |f|
        File.directory?(deploy_root + f) && ! f.match(/\A\.\.?\Z/)
      end
      most_recent_deploy = deploy_directories.sort_by{ |x| File.mtime(deploy_root + x) }.last
      deploy_root + most_recent_deploy
    end
  end
end
