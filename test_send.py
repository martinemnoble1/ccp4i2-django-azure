from azure.servicebus import ServiceBusClient, ServiceBusMessage

connection_string = "Endpoint=sb://ccp4i2-bicep-servicebus.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=EC3+t0hPRDHoWUH+G+wyW6xmfcV4Gjjam+ASbFcHeUI="

client = ServiceBusClient.from_connection_string(connection_string)

sender = client.get_queue_sender(queue_name="ccp4i2-bicep-jobs")

message = ServiceBusMessage("Test message from Python script")

sender.send_messages(message)

print("Message sent successfully")

sender.close()

client.close()