#include "CModemUSB.h"
#include <libusb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <arpa/inet.h>

#define VID 0x2ca3
#define PID 0x4006
struct fg_usb { libusb_context *context; libusb_device_handle *handle; unsigned char input, output; int claimed; };
static void fail(char *error, size_t capacity, const char *message) { if(error && capacity) snprintf(error, capacity, "%s", message); }
static double milliseconds(void) { struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1000.0+t.tv_nsec/1000000.0; }

int fg_command_allowed(const char *command) {
    const char *allowed[]={"AT","AT+QCFG=\"usbnet\"","AT+QCFG=\"usbnet\",0","AT+QCFG=\"usbnet\",1","AT+QCFG=\"qcautoconnect\"","AT+QCFG=\"qcautoconnect\",1","AT+CFUN=1,1"};
    if(!command)return 0;
    for(size_t i=0;i<sizeof(allowed)/sizeof(allowed[0]);i++)if(!strcmp(command,allowed[i]))return 1;
    return 0;
}
void fg_close(fg_usb *usb) {
    if(!usb)return;
    if(usb->claimed)libusb_release_interface(usb->handle,2);
    if(usb->handle)libusb_close(usb->handle);
    if(usb->context)libusb_exit(usb->context);
    free(usb);
}
fg_usb *fg_open(char *error,size_t capacity) {
    fg_usb *usb=calloc(1,sizeof(*usb));if(!usb){fail(error,capacity,"内存不足");return NULL;}
    if(libusb_init(&usb->context)<0){fail(error,capacity,"无法初始化 USB");fg_close(usb);return NULL;}
    libusb_device **devices=NULL;ssize_t count=libusb_get_device_list(usb->context,&devices);int found=0;
    libusb_device *target=NULL;
    if(count<0){fail(error,capacity,"无法枚举 USB 设备");fg_close(usb);return NULL;}
    for(ssize_t i=0;i<count;i++){struct libusb_device_descriptor d;if(!libusb_get_device_descriptor(devices[i],&d)&&d.idVendor==VID&&d.idProduct==PID){found++;target=devices[i];}}
    if(found!=1){fail(error,capacity,found?"请只连接一张大疆 4G 模块":"请连接大疆 4G 模块");libusb_free_device_list(devices,1);fg_close(usb);return NULL;}
    int result=libusb_open(target,&usb->handle);
    if(result<0){fail(error,capacity,result==LIBUSB_ERROR_ACCESS?"USB 访问被拒绝，请检查当前用户权限":"无法打开模块，请关闭其他网卡工具后重试");libusb_free_device_list(devices,1);fg_close(usb);return NULL;}
    struct libusb_config_descriptor *configuration=NULL;
    result=libusb_get_active_config_descriptor(target,&configuration);
    if(!result){
        for(int i=0;i<configuration->bNumInterfaces;i++)for(int j=0;j<configuration->interface[i].num_altsetting;j++){
            const struct libusb_interface_descriptor *a=&configuration->interface[i].altsetting[j];if(a->bInterfaceNumber!=2||a->bAlternateSetting!=0)continue;
            for(int k=0;k<a->bNumEndpoints;k++){
                const struct libusb_endpoint_descriptor *ep=&a->endpoint[k];if((ep->bmAttributes&LIBUSB_TRANSFER_TYPE_MASK)!=LIBUSB_TRANSFER_TYPE_BULK)continue;
                if(ep->bEndpointAddress&LIBUSB_ENDPOINT_IN)usb->input=ep->bEndpointAddress;else usb->output=ep->bEndpointAddress;
            }
        }
        libusb_free_config_descriptor(configuration);
    }
    libusb_free_device_list(devices,1);
    if(!usb->input||!usb->output){fail(error,capacity,"未发现已知的 AT 控制接口，已停止操作");fg_close(usb);return NULL;}
    result=libusb_claim_interface(usb->handle,2);
    if(result<0){fail(error,capacity,"控制接口被占用，请先退出 DJOneHub 或其他网卡工具");fg_close(usb);return NULL;}
    usb->claimed=1;
    return usb;
}
int fg_command(fg_usb *usb,const char *command,char *response,size_t capacity,unsigned timeout_ms,char *error,size_t error_capacity) {
    if(!usb||!response||capacity<2||!fg_command_allowed(command)){fail(error,error_capacity,"已拒绝未授权的 AT 指令");return -1;}
    unsigned char buffer[512];int transferred=0;
    // A bounded drain avoids matching the previous command's acknowledgement.
    for(int i=0;i<4;i++)if(libusb_bulk_transfer(usb->handle,usb->input,buffer,sizeof(buffer),&transferred,5)<0)break;
    char wire[128];snprintf(wire,sizeof(wire),"%s\r",command);
    int result=libusb_bulk_transfer(usb->handle,usb->output,(unsigned char*)wire,(int)strlen(wire),&transferred,1000);
    if(result<0||transferred!=(int)strlen(wire)){fail(error,error_capacity,"USB 写入中断，模块可能正在重连");return -2;}
    size_t used=0;response[0]=0;double start=milliseconds();
    while(milliseconds()-start<timeout_ms){
        transferred=0;result=libusb_bulk_transfer(usb->handle,usb->input,buffer,sizeof(buffer),&transferred,100);
        if(transferred>0){
            if(used+(size_t)transferred>=capacity){fail(error,error_capacity,"AT 响应过长，已停止解析");return -3;}
            memcpy(response+used,buffer,(size_t)transferred);used+=(size_t)transferred;response[used]=0;
            if(strstr(response,"\nOK\r")||strstr(response,"\nOK\n")||strstr(response,"\nERROR")||strstr(response,"\n+CME ERROR")||strstr(response,"\n+CMS ERROR"))return 0;
        }
        if(result<0&&result!=LIBUSB_ERROR_TIMEOUT){fail(error,error_capacity,"USB 连接中断，请等待模块重连");return -2;}
    }
    fail(error,error_capacity,"模块响应超时，请稍后刷新");return -4;
}
int fg_protocol_matches(int mode) {
    if(mode!=0&&mode!=1)return 0;
    libusb_context *context=NULL;if(libusb_init(&context)<0)return 0;
    libusb_device **devices=NULL;ssize_t count=libusb_get_device_list(context,&devices);int found=0,matches=0;
    for(ssize_t i=0;i<count;i++){
        struct libusb_device_descriptor d;if(libusb_get_device_descriptor(devices[i],&d)||d.idVendor!=VID||d.idProduct!=PID)continue;found++;
        struct libusb_config_descriptor *c=NULL;if(libusb_get_active_config_descriptor(devices[i],&c))continue;
        for(int j=0;j<c->bNumInterfaces;j++)for(int k=0;k<c->interface[j].num_altsetting;k++){
            const struct libusb_interface_descriptor *a=&c->interface[j].altsetting[k];if(a->bInterfaceNumber!=4)continue;
            if(mode==1&&a->bInterfaceClass==2&&a->bInterfaceSubClass==6)matches=1;
            if(mode==0&&a->bInterfaceClass==255&&a->bInterfaceSubClass==255)matches=1;
        }
        libusb_free_config_descriptor(c);
    }
    if(devices)libusb_free_device_list(devices,1);libusb_exit(context);return found==1&&matches;
}
static int number_property(io_registry_entry_t service,CFStringRef key) {
    CFTypeRef value=IORegistryEntryCreateCFProperty(service,key,kCFAllocatorDefault,0);int result=-1;
    if(value&&CFGetTypeID(value)==CFNumberGetTypeID())CFNumberGetValue((CFNumberRef)value,kCFNumberIntType,&result);
    if(value)CFRelease(value);return result;
}
static int belongs_to_module(io_registry_entry_t interface) {
    io_registry_entry_t current=interface;IOObjectRetain(current);
    for(int i=0;i<16;i++){
        if(number_property(current,CFSTR("idVendor"))==VID&&number_property(current,CFSTR("idProduct"))==PID){IOObjectRelease(current);return 1;}
        io_registry_entry_t parent=0;kern_return_t result=IORegistryEntryGetParentEntry(current,kIOServicePlane,&parent);IOObjectRelease(current);
        if(result!=KERN_SUCCESS)return 0;current=parent;
    }
    IOObjectRelease(current);return 0;
}
int fg_network_ready(void) {
    io_iterator_t iterator=0;if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IONetworkInterface"),&iterator)!=KERN_SUCCESS)return 0;
    io_service_t interface;int ready=0;
    while((interface=IOIteratorNext(iterator))){
        if(belongs_to_module(interface)){
            CFTypeRef name=IORegistryEntryCreateCFProperty(interface,CFSTR("BSD Name"),kCFAllocatorDefault,0);char bsd[128];
            if(name&&CFGetTypeID(name)==CFStringGetTypeID()&&CFStringGetCString((CFStringRef)name,bsd,sizeof(bsd),kCFStringEncodingUTF8)){
                struct ifaddrs *addresses=NULL;
                if(!getifaddrs(&addresses)){
                    for(struct ifaddrs *a=addresses;a;a=a->ifa_next)if(a->ifa_addr&&a->ifa_addr->sa_family==AF_INET&&(a->ifa_flags&IFF_UP)&&!strcmp(a->ifa_name,bsd)){
                        uint32_t ip=ntohl(((struct sockaddr_in*)a->ifa_addr)->sin_addr.s_addr);
                        if(ip&&((ip>>16)!=0xa9fe)&&((ip>>24)!=127))ready=1;
                    }
                    freeifaddrs(addresses);
                }
            }
            if(name)CFRelease(name);
        }
        IOObjectRelease(interface);
    }
    IOObjectRelease(iterator);return ready;
}
