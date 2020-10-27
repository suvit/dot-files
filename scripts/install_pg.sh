# -d в Заднем фоне
docker run -d \
           --name posgtresdb12 \
           -e POSTGRES_USER=viktor \
           -e POSTGRES_HOST_AUTH_METHOD=trust \
           -v /var/lib/postgresql/12-docker/main:/var/lib/postgresql/data \
           -p 127.0.0.1:65432:5432 \
           postgres:12 \
           -c 'shared_buffers=256MB' -c 'max_locks_per_transaction=256'
