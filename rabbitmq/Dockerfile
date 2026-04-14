FROM rabbitmq:4.2.4-management

ENV RABBITMQ_CONFIG_FILE /etc/rabbitmq/clusterrabbitmq.conf
COPY config.conf /etc/rabbitmq/clusterrabbitmq.conf
COPY definitions.json /etc/rabbitmq/clusterdefinitions.json