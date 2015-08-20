class VcenterController < ApplicationController

  def index
  end

       def find_vm(folder, vmname)
        children = folder.children.find_all
        children.each do |child|
          if child.class == RbVmomi::VIM::VirtualMachine && child.name == vmname
            return child
          elsif child.class == RbVmomi::VIM::Folder
            vm = find_vm(child, vmname)
            return vm if vm
          end
        end
        false
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

  def number_to_human_size(number)
    number = number.to_f
    storage_units_fmt = %w(byte kB MB GB TB)
    base = 1024
    if number.to_i < base
      unit = storage_units_fmt[0]
    else
      max_exp = storage_units_fmt.size - 1
      exponent = (Math.log(number) / Math.log(base)).to_i # Convert to base
      exponent = max_exp if exponent > max_exp # we need this to avoid overflow for the highest unit
      number /= base**exponent
      unit = storage_units_fmt[exponent]
    end
    format('%0.2f %s', number, unit)
  end

  def find_datastores
    connect_to_vcenter
    dc = connect_to_dc
    arr = []
    dc.datastore.each do |store|
      arr << {:name => store.name, :avail => number_to_human_size(store.summary[:freeSpace]), :cap => number_to_human_size(store.summary[:capacity])}
    end
    arr
  end

  def get_hosts
		hosts = find_pools(connect_to_dc.hostFolder).flatten
		render json: {hosts: hosts}
  end

	def get_vms
		vms = traverse_folders_for_vms(connect_to_dc.vmFolder)
		render json: {vms: vms, count: vms.count}
	end

  def get_templates
    templates = traverse_folders_for_templates(connect_to_dc.vmFolder)
    render json: {templates: templates}
  end

  def list_datastores
    datastores = find_datastores
    render json: {datastores: datastores, count: datastores.count}
  end



  def power_on_vm
   connect_to_vcenter
  dc = connect_to_dc
  vm = find_vm(dc.vmFolder, params[:vm])
  vm.PowerOnVM_Task.wait_for_completion
  render nothing: true
  end

  def power_off_vm
    connect_to_vcenter
  dc = connect_to_dc
  vm = find_vm(dc.vmFolder, params[:vm])
  vm.PowerOffVM_Task.wait_for_completion
  render nothing: true
  end

	private
	def connect_to_vcenter
    @vim = RbVmomi::VIM.connect host: '192.168.102.48', user: 'administrator', password: 'Vcenter@123', ssl: 'false', insecure: 'true'
	end

	def connect_to_dc
		@dc = connect_to_vcenter.serviceInstance.find_datacenter("DC1") or fail "datacenter not found"
	end

end
