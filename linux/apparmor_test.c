#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <sys/ptrace.h>
#include <netinet/in.h>
#include <string.h>
#include <arpa/inet.h>


//write_to_file
void write_to_file() {
    FILE *fp = fopen("/tmp/demo_output.txt", "w");
    if (fp) {
        fprintf(fp, "This is a sample output.\n");
        fclose(fp);
        printf("[+] write_to_file - Wrote to /tmp/demo_output.txt\n");
    } else {
        perror("[-] write_to_file - Failed to write to file");
    }
}

//read_sensitive_file
void read_sensitive_file() {
    FILE *fp = fopen("/etc/shadow", "r");
    if (fp) {
        printf("[+] read_sensitive_file - Able to read /etc/shadow \n");
        fclose(fp);
    } else {
        perror("[-] read_sensitive_file - Failed to read /etc/shadow");
    }
}

//make_syscall
void make_syscall() {
    pid_t pid = syscall(SYS_getpid);
    printf("[+] make_syscall - Syscall SYS_getpid returned: %d\n", pid);
}

//use_network
void use_network() {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("[-] use_network - Socket creation failed");
        return;
    }

    struct sockaddr_in target;
    target.sin_family = AF_INET;
    target.sin_port = htons(80);  // SMTP
    inet_pton(AF_INET, "1.1.1.1", &target.sin_addr);

    if (connect(sock, (struct sockaddr *)&target, sizeof(target)) == 0) {
        printf("[+] use_network - Network connection established to 1.1.1.1:80\n");
    } else {
        perror("[-] use_network - Network connection failed");
    }

    close(sock);
}

//use_ptrace
void use_ptrace() {
    long ret = ptrace(PTRACE_TRACEME, 0, NULL, NULL);
    if (ret == 0) {
        printf("[+] use_ptrace - ptrace(PTRACE_TRACEME) succeeded\n");
    } else {
        perror("[-] use_ptrace - ptrace failed");
    }
}

int main() {
    printf("=== Demo App Starting ===\n");
    write_to_file();
    read_sensitive_file();
    make_syscall();
    use_network();
    use_ptrace();
    printf("=== Demo App Completed ===\n");

    return 0;
}
