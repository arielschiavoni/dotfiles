function cleanup_docker --description 'Removes all unsed docker images, containers and volumes'
   echo "removing stopped containers..."
   docker container prune --force

   echo "removing images..."
   docker rmi (docker images -f "dangling=true" -q)

   echo "removing volumes..."
   docker volume prune --force

   echo "done!" 
end
