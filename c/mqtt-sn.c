/* Minimal MQTT-SN Send QoS=-1 */

#include <sys/socket.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int MqttSN_sockfd;
struct sockaddr_in MqttSN_server;
#define MAX_MSG_LEN 64

int MqttSN_open_socket(char *host, int port) {
   MqttSN_sockfd=socket(AF_INET,SOCK_DGRAM,0);
   bzero(&MqttSN_server,sizeof(MqttSN_server));
   MqttSN_server.sin_family = AF_INET;
   MqttSN_server.sin_addr.s_addr=inet_addr(host);
   MqttSN_server.sin_port=htons(port);
}

int MqttSN_pub(char *topic, char *msg) {
   unsigned char buf[MAX_MSG_LEN];
   if (strlen(msg)+7>MAX_MSG_LEN) {
      printf("Error: too long message!\n");
      exit(-1);
   }
   if (strlen(topic)!=2) {
      printf("Error: Topic must be two characters!\n");
      exit(-1);
   }
   buf[0]=strlen(msg)+7; //len
   buf[1]=0x0c; // msg type= publish
   buf[2]=0x62; // flags
   buf[3]=topic[0]; // topic , 2 char
   buf[4]=topic[1];
   buf[5]=0x00;
   buf[6]=0x01;
   strcpy(&buf[7],msg);
   sendto(MqttSN_sockfd,buf,buf[0],0,(struct sockaddr *)&MqttSN_server,sizeof(MqttSN_server));
}
