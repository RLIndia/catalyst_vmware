
#Copyright [2016] [Relevance Lab]
#loLicensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at

#http://www.apache.org/licenses/LICENSE-2.0

#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.



Rails.application.routes.draw do
  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
   root 'vcenter#index'
   get 'validate_creds' => 'vcenter#validate_creds'
   get 'vms' => 'vcenter#get_vms'
   get ':vm/info' => 'vcenter#vm_info'
   get 'templates' => 'vcenter#get_templates'
   get 'hosts' => 'vcenter#get_hosts'
   get 'datastores' => 'vcenter#list_datastores'
   get 'clusters' => 'vcenter#list_clusters'
   put ':vm/poweron' => 'vcenter#power_on_vm'
   put ':vm/poweroff' => 'vcenter#power_off_vm'
   post ':template/clone' => 'vcenter#clone_vm'
   delete ':vm/delete' => 'vcenter#delete_vm'
  
end
