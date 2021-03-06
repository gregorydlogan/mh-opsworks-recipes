# Cookbook Name:: mh-opsworks-recipes
# Recipe:: create-alerts-from-opsworks-metrics

include_recipe "awscli::default"
::Chef::Resource::RubyBlock.send(:include, MhOpsworksRecipes::RecipeHelpers)

ruby_block "add alarms" do
  block do
    aws_instance_id = node[:opsworks][:instance][:aws_instance_id]
    # All opsworks metrics are sent to us-east-1, so we need to write alarms
    # off this region
    region = 'us-east-1'

    # Instance properties for monitoring
    number_of_cpus = %x(nproc).chomp.to_i
    total_ram = %x(grep MemTotal /proc/meminfo | sed -r 's/[^0-9]//g').chomp.to_i
    local_file_systems=%x(mount | grep -E 'type ext|type xfs' | cut -f3 -d' ').chomp.split(/\n/)

    # Thresholds for monitoring targets
    disk_free_threshold = 20
    # As a percentage
    memory_limit = get_memory_limit
    load_limit = number_of_cpus * 1.5

    # This is idempotent according to the aws docs
    topic_arn = %x(aws sns create-topic --name "#{topic_name}" --region #{region} --output text).chomp

    command = %Q(aws cloudwatch put-metric-alarm --region "#{region}" --alarm-name "#{alarm_name_prefix}_load_5_high" --alarm-description "Load 5 is high on #{alarm_name_prefix}" --metric-name Load5 --namespace AWS/OpsworksCustom --statistic Average --period 240 --threshold #{load_limit} --comparison-operator GreaterThanThreshold --dimensions Name=InstanceId,Value=#{aws_instance_id} --evaluation-periods 1 --alarm-actions "#{topic_arn}")
    Chef::Log.info command
    %x(#{command})

    command = %Q(aws cloudwatch put-metric-alarm --region "#{region}" --alarm-name "#{alarm_name_prefix}_memory_used_high" --alarm-description "Memory usage is high on #{alarm_name_prefix}" --metric-name MemoryUsed --namespace AWS/OpsworksCustom --statistic Average --period 240 --threshold #{memory_limit} --comparison-operator GreaterThanThreshold --dimensions Name=InstanceId,Value=#{aws_instance_id} --evaluation-periods 1 --alarm-actions "#{topic_arn}" --unit Percent)
    Chef::Log.info command
    %x(#{command})

    local_file_systems.each do |partition_mount|
      metric_name = ''
      if partition_mount == '/'
        metric_name = 'SpaceFreeOnRootPartition'
      else
        metric_suffix = partition_mount.gsub(/[^a-z\d]/,'_')
        metric_name = "SpaceFreeOn#{metric_suffix}"
      end
      command = %Q(aws cloudwatch put-metric-alarm --region "#{region}" --alarm-name "#{alarm_name_prefix}_#{metric_name}" --alarm-description "#{metric_name} running low on #{alarm_name_prefix}" --metric-name "#{metric_name}" --namespace AWS/OpsworksCustom --statistic Average --period 240 --threshold #{disk_free_threshold} --comparison-operator LessThanThreshold --dimensions Name=InstanceId,Value=#{aws_instance_id} --evaluation-periods 1 --alarm-actions "#{topic_arn}" --unit Percent)
      Chef::Log.info command
      %x(#{command})
    end

    if ::File.exists?('/etc/mdadm/mdadm.conf')
      # Using software raid - add the raid sync metric alarm
      command = %Q(aws cloudwatch put-metric-alarm --region "#{region}" --alarm-name "#{alarm_name_prefix}_raid_array_sync" --alarm-description "Software RAID arrays out of sync on #{alarm_name_prefix}" --metric-name RAIDArrayInSync --namespace AWS/OpsworksCustom --statistic Minimum --period 120 --threshold 1 --comparison-operator LessThanThreshold --dimensions Name=InstanceId,Value=#{aws_instance_id} --evaluation-periods 1 --alarm-actions "#{topic_arn}")
      Chef::Log.info command
      %x(#{command})
    end

    if admin_node?
      # Create a mysql availability ping
      command = %Q(aws cloudwatch put-metric-alarm --region "#{region}" --alarm-name "#{alarm_name_prefix}_mysql_availablity" --alarm-description "MySQL is unavailable #{alarm_name_prefix}" --metric-name MySQLServerAvailable --namespace AWS/OpsworksCustom --statistic Minimum --period 120 --threshold 1 --comparison-operator LessThanThreshold --dimensions Name=InstanceId,Value=#{aws_instance_id} --evaluation-periods 1 --alarm-actions "#{topic_arn}")
      Chef::Log.info command
      %x(#{command})
    end
  end
end
