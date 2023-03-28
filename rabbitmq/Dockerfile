FROM rabbitmq:3.11.11-management

ENV RABBITMQ_CONFIG_FILE /etc/rabbitmq/clusterrabbitmq.conf
COPY config.conf /etc/rabbitmq/clusterrabbitmq.conf
COPY definitions.json /etc/rabbitmq/clusterdefinitions.json