/* Minimal MQTT-SN Send QoS=-1 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "mqtt-sn.h"

/*
MQTT-SN minimal c-client-library: 
Copyright (C) 2014  Ari Siitonen

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

int main(int argc, char**argv)
{
   if (argc != 5)
   {
      printf("usage: mqtt-sn-pub Ip Port Topic Msg \n");
      exit(1);
   }
   MqttSN_open_socket(argv[1],atoi(argv[2]));
   MqttSN_pub(argv[3],argv[4]);
   printf("Published '%s' with topic '%s' to mqtt-sn server '%s:%d'\n",argv[4],argv[3],argv[1],atoi(argv[2]));
}