function add_ssh_agent --description 'Add ssh key to ssh-agent'
  eval (ssh-agent -c)
  ssh-add ~/.ssh/id_rsa 
end
