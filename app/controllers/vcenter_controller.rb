class VcenterController < ApplicationController

  def index
  end

  def traverse_folders_for_vms(folder)
  	connect_to_vcenter
    connect_to_dc
    retval = []
    children = folder.children.find_all
    children.each do |child|
      if child.class == RbVmomi::VIM::VirtualMachine 
        retval << {:name => child.name, :ip => child.guest_ip, :OS => child.guest.props[:guestFullName], :state => child.summary.runtime.powerState, :cpuUsage => child.summary.quickStats.overallCpuUsage, :uptime => child.summary.quickStats.uptimeSeconds}
      elsif child.class == RbVmomi::VIM::Folder
        retval.concat(traverse_folders_for_vms(child))
      end
    end
		retval
  end

  def traverse_folders_for_templates(folder)
  	connect_to_vcenter
    connect_to_dc
    retval = []
    children = folder.children.find_all
    children.each do |child|
      if child.class == RbVmomi::VIM::VirtualMachine 
        retval << child.name if (!child.config.nil? && child.config.template == true)
      elsif child.class == RbVmomi::VIM::Folder
        retval.concat(traverse_folders_for_templates(child))
      end
    end
    retval
  end

  def find_pools(folder)
  	connect_to_vcenter
    connect_to_dc
		arr = []
		pools = folder.children.find_all.select { |p| p.is_a?(RbVmomi::VIM::ComputeResource) || p.is_a?(RbVmomi::VIM::ResourcePool) }.map(&:host)
	  pools.each do |pool|
		 # arr << {:name => pool.map(&:name), :memory => pool.map(&:hardware).map(&:memorySize).map(&:bytes)}
	   arr << pool.map(&:name)
   end
	  arr
  end

  def get_hosts
		hosts = find_pools(connect_to_dc.hostFolder).flatten
		render json: {hosts: hosts}
  end

	def get_vms
    puts request.headers.inspect
    p request.headers['HTTP_VCENTER_IP']
    p "==================================="
		vms = traverse_folders_for_vms(connect_to_dc.vmFolder)
		render json: {vms: vms, count: vms.count}
	end

  def get_templates
    templates = traverse_folders_for_templates(connect_to_dc.vmFolder)
    render json: {templates: templates}
  end

  def power_on_vm
   connect_to_vcenter
  dc = connect_to_dc
    vm = dc.find_vm("#{params["vm"]}") or fail "VM not found"
    vm.PowerOnVM_Task.wait_for_completion
  end

	private
	def connect_to_vcenter
    @vim = RbVmomi::VIM.connect host: '192.168.102.48', user: 'administrator', password: 'Vcenter@123', ssl: 'false', insecure: 'true'
	end

	def connect_to_dc
		@dc = connect_to_vcenter.serviceInstance.find_datacenter("DC1") or fail "datacenter not found"
	end

end
