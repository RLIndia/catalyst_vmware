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
 

  
  def find_pools(folder)
		arr = []
		pools = folder.children.find_all.select { |p| p.is_a?(RbVmomi::VIM::ComputeResource) || p.is_a?(RbVmomi::VIM::ResourcePool) }.map(&:host)
	  pools.each do |pool|
      pool.each do |host|
		 # arr << {:name => pool.map(&:name), :memory => pool.map(&:hardware).map(&:memorySize).map(&:bytes)}
	   arr << {:name => host.name, :vms => host.vm.map(&:name), :memory => VcenterHelper.number_to_human_size(host.hardware.memorySize), :cpuUsage => host.summary.quickStats.overallCpuUsage, :state => host.summary.runtime.powerState, :cpu_cores => host.hardware.cpuInfo.numCpuCores
}
   end
 end
	  arr
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

  def find_clusters(folder)
    arr = []
    clusters = find_all_in_folder(folder, RbVmomi::VIM::ClusterComputeResource)
    clusters.each do |cluster|
      arr << {:name => cluster.name, :hosts => cluster.host.map(&:name)}
    end
    arr
  end

  def find_datastores(dc)
    arr = []
    dc.datastore.each do |store|
      arr << {:name => store.name, :avail => VcenterHelper.number_to_human_size(store.summary[:freeSpace]), :cap => VcenterHelper.number_to_human_size(store.summary[:capacity])}
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
    vms = VcenterHelper.traverse_folders_for_vms(dc.vmFolder)
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
    templates = VcenterHelper.traverse_folders_for_templates(dc.vmFolder)
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

  def list_clusters
    begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
    rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
    end
    clusters = find_clusters(dc.hostFolder)
    render json: {clusters: clusters, count: clusters.count}
  end

  def power_on_vm
  begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
    rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
  end
  vm = VcenterHelper.find_vm(dc.vmFolder, params[:vm])
  begin
  vm.PowerOnVM_Task.wait_for_completion
  rescue NoMethodError 
    render text: "VM not found", status: 404
    return
  end
  render nothing: true, status:200
  end

  def power_off_vm
  begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
    rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
  end
  vm = VcenterHelper.find_vm(dc.vmFolder, params[:vm])
  begin
  vm.PowerOffVM_Task.wait_for_completion
  rescue NoMethodError 
    render text: "VM not found", status: 404
    return
  end
  render nothing: true, status:200
  end

  def delete_vm
    begin
    dc = connect_to_vcenter.serviceInstance.find_datacenter(params[:dc]) or fail "datacenter not found"
    rescue NoMethodError
      return
    rescue RuntimeError => e
      render json: "#{e.message}", status:404
      return
    end
    begin
    vm = VcenterHelper.find_vm(dc.vmFolder, params[:vm])
    vm.PowerOffVM_Task.wait_for_completion unless vm.runtime.powerState == 'poweredOff'
    rescue NoMethodError 
      render text: "VM not found", status: 404
      return
    end
    vm.Destroy_Task.wait_for_completion
    render nothing:true, status:200
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
    vm = VcenterHelper.find_vm(dc.vmFolder, params[:template])
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
