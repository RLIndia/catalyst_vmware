class VcenterController < ApplicationController

  def index
  end

  def validate_creds
    begin
      vim = RbVmomi::VIM.connect host: params[:ip], user: params[:user], password: params[:passwd], ssl: 'false', insecure: 'true'
      rescue Errno::ECONNREFUSED => e
        render text: "#{e.message}", status: 400
        return
      rescue RbVmomi::Fault => e
        render text: "#{e.message}", status: 400
        return
    end
    begin
      dc = vim.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
      rescue RuntimeError => e
      render text: "#{e.message}", status: 404
      return
    end
      render text: "Validated", status:200
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
    retval = []
    children = folder.children.find_all
    children.each do |child|
      if child.class == RbVmomi::VIM::VirtualMachine 
        retval << {:name => child.name, :ip => child.guest_ip, :OS => child.guest.props[:guestFullName], :state => child.summary.runtime.powerState, :cpuUsage => child.summary.quickStats.overallCpuUsage, :uptime => child.summary.quickStats.uptimeSeconds} if (!child.config.nil? && child.config.template == false)
      elsif child.class == RbVmomi::VIM::Folder
        retval.concat(traverse_folders_for_vms(child))
      end
    end
		retval
  end

  def traverse_folders_for_templates(folder)
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

  def find_all_in_folder(folder, type)
    if folder.instance_of?(RbVmomi::VIM::ClusterComputeResource) || folder.instance_of?(RbVmomi::VIM::ComputeResource)
      folder = folder.resourcePool
    end
    if folder.instance_of?(RbVmomi::VIM::ResourcePool)
      folder.resourcePool.grep(type)
    elsif folder.instance_of?(RbVmomi::VIM::Folder)
      folder.childEntity.grep(type)
    else
      puts "Unknown type #{folder.class}, not enumerating"
      nil
    end
  end

  def find_datastores(dc)
    arr = []
    dc.datastore.each do |store|
      arr << {:name => store.name, :avail => number_to_human_size(store.summary[:freeSpace]), :cap => number_to_human_size(store.summary[:capacity])}
    end
    arr
  end

  def get_hosts
  begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
    rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
    end
    hosts = find_pools(dc.hostFolder).flatten
		render json: {hosts: hosts, count: hosts.count}
  end

	def get_vms
    begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
		rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
    end
    vms = traverse_folders_for_vms(dc.vmFolder)
		render json: {vms: vms, count: vms.count}
	end

  def get_templates
    begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
    rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
    end
    templates = traverse_folders_for_templates(dc.vmFolder)
    render json: {templates: templates, count: templates.count}
  end

  def list_datastores
    begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
    rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
    end
    datastores = find_datastores(dc)
    render json: {datastores: datastores, count: datastores.count}
  end



  def power_on_vm
  dc = connect_to_dc
  vm = find_vm(dc.vmFolder, params[:vm])
  vm.PowerOnVM_Task.wait_for_completion
  render nothing: true
  end

  def power_off_vm
  dc = connect_to_dc
  vm = find_vm(dc.vmFolder, params[:vm])
  vm.PowerOffVM_Task.wait_for_completion
  render nothing: true
  end

  def clone_vm
    connect_to_vcenter
    dc = connect_to_dc
    req = JSON.parse(request.body.read)
    hosts = find_all_in_folder(dc.hostFolder, RbVmomi::VIM::ComputeResource)
    raise "No ComputeResource found" if hosts.empty?
    rp = nil
    hosts.each do |host|
      host.datastore.each do |datastore|
        if datastore.name == req[:datastore]
          rp = host.resourcePool
        end
      end
    end
    rspec = RbVmomi::VIM.VirtualMachineRelocateSpec(pool:rp)
    rspec.datastore = req["datastore"]
    spec = RbVmomi::VIM.VirtualMachineCloneSpec(location: rspec, powerOn: false, template: false)
    vm = find_vm(dc.vmFolder, params[:template])
    p vm
    p vm.parent.class
    vm.CloneVM_Task(:folder => vm.parent, :name => req["vm_name"], :spec => spec).wait_for_completion
    render nothing:true
  end

	private
	def connect_to_vcenter
    begin
    @vim = RbVmomi::VIM.connect host: params[:ip], user: params[:user], password: params[:passwd], ssl: 'false', insecure: 'true'
 	  rescue Errno::ECONNREFUSED => e
        render text: "#{e.message}", status: 400
        return
      rescue RbVmomi::Fault => e
        render text: "#{e.message}", status: 400
        return 
    rescue RuntimeError
      render nothing:true, status:400
      return
    end
    @vim
  end
end
