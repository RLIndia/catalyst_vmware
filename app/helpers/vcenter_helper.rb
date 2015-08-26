module VcenterHelper
	def self.traverse_folders_for_vms(folder)
    retval = []
    children = folder.children.find_all
    children.each do |child|
      if child.class == RbVmomi::VIM::VirtualMachine 
        retval << {:name => child.name, :ip => child.guest_ip, :OS => child.guest.props[:guestFullName], :toolsStatus => child.guest.toolsRunningStatus, :state => child.summary.runtime.powerState, :cpuUsage => {:used => child.summary.quickStats.overallCpuUsage,:num => child.config.hardware.numCPU},:memory => {:avail => child.config.hardware.memoryMB, :used => child.summary.quickStats.guestMemoryUsage}, :uptime => child.summary.quickStats.uptimeSeconds} if (!child.config.nil? && child.config.template == false)
      elsif child.class == RbVmomi::VIM::Folder
        retval.concat(traverse_folders_for_vms(child))
      end
    end
		retval
  end

  def self.find_vm(folder, vmname)
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

def self.traverse_folders_for_templates(folder)
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

def self.number_to_human_size(number)
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

end
