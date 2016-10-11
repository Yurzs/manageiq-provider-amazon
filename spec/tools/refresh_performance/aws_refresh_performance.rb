require_relative '../../models/manageiq/providers/amazon/aws_helper'
require_relative '../../models/manageiq/providers/amazon/aws_stubs'

describe ManageIQ::Providers::Amazon::NetworkManager::Refresher do
  include AwsStubs

  describe "refresh" do
    before(:each) do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryGirl.create(:ems_amazon, :zone => zone, :name => ems_name)
      @ems.update_authentication(:default => {:userid => "0123456789", :password => "ABCDEFGHIJKL345678efghijklmno"})
    end

    before(:all) do
      output = ["Name", "Object Count", "Scaling", "Collect", "Parse Legacy", "Parse Targetted", "Saving", "Total"]

      open(Rails.root.join('log', 'benchmark_results.csv'), 'a') do |f|
        f.puts output.join(",")
      end
    end

    let(:ec2_user) { FactoryGirl.build(:authentication).userid }
    let(:ec2_pass) { FactoryGirl.build(:authentication).password }
    let(:ec2_user_other) { 'user_other' }
    let(:ec2_pass_other) { 'pass_other' }
    subject { described_class.discover(ec2_user, ec2_pass) }

    before do
      EvmSpecHelper.local_miq_server(:zone => Zone.seed)

      stub_load_balancer_service
    end

    around do |example|
      with_aws_stubbed(:ec2 => stub_responses) do
        example.run
      end
    end

    context "with data scaled 1x" do
      let(:data_scaling) { 1 }
      let(:ems_name) { "ems_scaled_1x" }

      it "will perform a full refresh" do
        refresh
      end
    end

    context "with data scaled 2x" do
      let(:data_scaling) { 2 }
      let(:ems_name) { "ems_scaled_2x" }

      it "will perform a full refresh" do
        refresh
      end
    end

    context "with data scaled 3x" do
      let(:data_scaling) { 3 }
      let(:ems_name) { "ems_scaled_3x" }

      it "will perform a full refresh" do
        refresh
      end
    end

    context "with data scaled 5x" do
      let(:data_scaling) { 5 }
      let(:ems_name) { "ems_scaled_5x" }

      it "will perform a full refresh" do
        refresh
      end
    end

    context "with data scaled 10x" do
      let(:data_scaling) { 10 }
      let(:ems_name) { "ems_scaled_10x" }

      it "will perform a full refresh" do
        refresh
      end
    end

    context "with data scaled 20x" do
      let(:data_scaling) { 20 }
      let(:ems_name) { "ems_scaled_20x" }

      it "will perform a full refresh" do
        refresh
      end
    end
  end

  def refresh
    EmsRefresh.refresh(@ems.network_manager)
    @ems.reload
    write_benchmark_results

    assert_table_counts
    assert_ems
  end

  def write_benchmark_results
    detected = File.readlines(Rails.root.join('log', 'evm.log')).reverse_each.detect do |s|
      s.include?(ems_name) && s.include?("Complete - Timings")
    end

    open(Rails.root.join('log', 'benchmark_results.log'), 'a') do |f|
      f.puts detected
    end

    # Get also a chart displayable format
    matched = detected.match(/:collect_inventory_for_targets=>([\d\.e-]+).*?
                              :parse_legacy_inventory=>([\d\.e-]+).*?
                              :parse_targeted_inventory=>([\d\.e-]+).*?
                              :save_inventory=>([\d\.e-]+).*?
                              :ems_refresh=>([\d\.e-]+).*?/x)
    output = []
    output << "Scaling #{scaling_factor} total_objects #{expected_table_counts.values.sum}"
    output << expected_table_counts.values.sum
    output << scaling_factor
    output += matched[1..5].map { |x| x.to_f.round(2) }
    open(Rails.root.join('log', 'benchmark_results.csv'), 'a') do |f|
      f.puts output.join(",")
    end
  end

  def stub_responses
    {
      :describe_regions            => {
        :regions => [
          {:region_name => 'us-east-1'},
          {:region_name => 'us-west-1'},
        ]
      },
      :describe_instances          => mocked_instances,
      :describe_vpcs               => mocked_vpcs,
      :describe_subnets            => mocked_subnets,
      :describe_security_groups    => mocked_security_groups,
      :describe_network_interfaces => mocked_network_ports,
      :describe_addresses          => mocked_floating_ips
    }
  end

  def expected_table_counts
    firewall_rule_count = test_counts[:security_group_count] *
      (test_counts[:outbound_firewall_rule_per_security_group_count] +
        test_counts[:outbound_firewall_rule_per_security_group_count])

    {
      :auth_private_key                  => 0,
      :ext_management_system             => 2,
      :flavor                            => 0,
      :availability_zone                 => 0,
      :vm_or_template                    => 0,
      :vm                                => 0,
      :miq_template                      => 0,
      :disk                              => 0,
      :guest_device                      => 0,
      :hardware                          => 0,
      :network                           => 0,
      :operating_system                  => 0,
      :snapshot                          => 0,
      :system_service                    => 0,
      :relationship                      => 195,
      :miq_queue                         => 3,
      :orchestration_template            => 1,
      :orchestration_stack               => 0,
      :orchestration_stack_parameter     => 0,
      :orchestration_stack_output        => 0,
      :orchestration_stack_resource      => 0,
      :security_group                    => test_counts[:security_group_count],
      :firewall_rule                     => firewall_rule_count,
      :network_port                      => test_counts[:instance_ec2_count] + test_counts[:network_port_count],
      :cloud_network                     => test_counts[:vpc_count],
      :floating_ip                       => test_counts[:floating_ip_count] + test_counts[:network_port_count],
      :network_router                    => 0,
      :cloud_subnet                      => test_counts[:subnet_count],
      :custom_attribute                  => 0,
      :load_balancer                     => test_counts[:load_balancer_count],
      :load_balancer_pool                => test_counts[:load_balancer_count],
      :load_balancer_pool_member         => test_counts[:load_balancer_instances_count],
      :load_balancer_pool_member_pool    => test_counts[:load_balancer_count] * test_counts[:load_balancer_instances_count],
      :load_balancer_listener            => test_counts[:load_balancer_count],
      :load_balancer_listener_pool       => test_counts[:load_balancer_count],
      :load_balancer_health_check        => test_counts[:load_balancer_count],
      :load_balancer_health_check_member => test_counts[:load_balancer_count] * test_counts[:load_balancer_instances_count],
    }
  end

  def assert_table_counts
    actual = {
      :auth_private_key                  => AuthPrivateKey.count,
      :ext_management_system             => ExtManagementSystem.count,
      :flavor                            => Flavor.count,
      :availability_zone                 => AvailabilityZone.count,
      :vm_or_template                    => VmOrTemplate.count,
      :vm                                => Vm.count,
      :miq_template                      => MiqTemplate.count,
      :disk                              => Disk.count,
      :guest_device                      => GuestDevice.count,
      :hardware                          => Hardware.count,
      :network                           => Network.count,
      :operating_system                  => OperatingSystem.count,
      :snapshot                          => Snapshot.count,
      :system_service                    => SystemService.count,
      :relationship                      => Relationship.count,
      :miq_queue                         => MiqQueue.count,
      :orchestration_template            => OrchestrationTemplate.count,
      :orchestration_stack               => OrchestrationStack.count,
      :orchestration_stack_parameter     => OrchestrationStackParameter.count,
      :orchestration_stack_output        => OrchestrationStackOutput.count,
      :orchestration_stack_resource      => OrchestrationStackResource.count,
      :security_group                    => SecurityGroup.count,
      :firewall_rule                     => FirewallRule.count,
      :network_port                      => NetworkPort.count,
      :cloud_network                     => CloudNetwork.count,
      :floating_ip                       => FloatingIp.count,
      :network_router                    => NetworkRouter.count,
      :cloud_subnet                      => CloudSubnet.count,
      :custom_attribute                  => CustomAttribute.count,
      :load_balancer                     => LoadBalancer.count,
      :load_balancer_pool                => LoadBalancerPool.count,
      :load_balancer_pool_member         => LoadBalancerPoolMember.count,
      :load_balancer_pool_member_pool    => LoadBalancerPoolMemberPool.count,
      :load_balancer_listener            => LoadBalancerListener.count,
      :load_balancer_listener_pool       => LoadBalancerListenerPool.count,
      :load_balancer_health_check        => LoadBalancerHealthCheck.count,
      :load_balancer_health_check_member => LoadBalancerHealthCheckMember.count,
    }

    expect(actual).to eq expected_table_counts
  end

  def assert_ems
    ems = @ems.network_manager

    expect(ems).to have_attributes(
      :api_version => nil, # TODO: Should be 3.0
      :uid_ems     => nil
    )

    expect(ems.flavors.size).to eql(expected_table_counts[:flavor])
    expect(ems.availability_zones.size).to eql(expected_table_counts[:availability_zone])
    expect(ems.vms_and_templates.size).to eql(expected_table_counts[:vm_or_template])
    expect(ems.security_groups.size).to eql(expected_table_counts[:security_group])
    expect(ems.network_ports.size).to eql(expected_table_counts[:network_port])
    expect(ems.cloud_networks.size).to eql(expected_table_counts[:cloud_network])
    expect(ems.floating_ips.size).to eql(expected_table_counts[:floating_ip])
    expect(ems.network_routers.size).to eql(expected_table_counts[:network_router])
    expect(ems.cloud_subnets.size).to eql(expected_table_counts[:cloud_subnet])
    expect(ems.miq_templates.size).to eq(expected_table_counts[:miq_template])

    expect(ems.orchestration_stacks.size).to eql(expected_table_counts[:orchestration_stack])

    expect(ems.load_balancers.size).to eql(expected_table_counts[:load_balancer])
  end
end
