# -d в Заднем фоне
docker run -d \
           --name postgresdb16 \
           --shm-size=1g \
           -e POSTGRES_USER=$USER \
           -e POSTGRES_HOST_AUTH_METHOD=trust \
           -v /var/lib/postgresql/16-docker/main:/var/lib/postgresql/data \
           -p 127.0.0.1:16432:5432 \
           postgres:16 \
           -c 'shared_buffers=256MB' -c 'max_locks_per_transaction=256' \
           -c 'random_page_cost=1.1'
           # -c 'max_parallel_workers_per_gather=0'

# Как убить контейнер?
# docker stop postgresdb16
# docker rm postgresdb16
