/* Minimal MQTT-SN Send QoS=-1 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char**argv)
{
   if (argc != 5)
   {
      printf("usage: pub Ip Port Topic Msg \n");
      exit(1);
   }
   MqttSN_open_socket(argv[1],atoi(argv[2]));
   MqttSN_pub(argv[3],argv[4]);
}