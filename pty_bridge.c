#include <vpi_user.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <util.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static int pty_master = -1;
static int pty_slave  = -1;
static char pty_slave_path[128] = {0};
static int server_sock = -1;
static int client_sock = -1;

static PLI_INT32 term_init_calltf(char *user_data) {
    (void)user_data;

    // 1. Setup macOS PTY
    if (openpty(&pty_master, &pty_slave, pty_slave_path, NULL, NULL) == 0) {
        int flags = fcntl(pty_master, F_GETFL, 0);
        fcntl(pty_master, F_SETFL, flags | O_NONBLOCK);

        struct termios t;
        tcgetattr(pty_master, &t);
        cfmakeraw(&t);
        tcsetattr(pty_master, TCSANOW, &t);

        unlink("/tmp/rv32_console");
        symlink(pty_slave_path, "/tmp/rv32_console");
    }

    // 2. Setup TCP Server on 127.0.0.1:9000
    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (server_sock >= 0) {
        int opt = 1;
        setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = inet_addr("127.0.0.1");
        addr.sin_port = htons(9000);

        if (bind(server_sock, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            listen(server_sock, 1);
            int flags = fcntl(server_sock, F_GETFL, 0);
            fcntl(server_sock, F_SETFL, flags | O_NONBLOCK);
        } else {
            close(server_sock);
            server_sock = -1;
        }
    }

    printf("\n============================================================\n");
    printf(" [VPI] RV32I Virtual Terminal Active!\n");
    printf(" Connect to the simulated computer using:\n");
    printf("   1) nc localhost 9000             (Recommended)\n");
    if (pty_slave_path[0]) {
        printf("   2) screen /tmp/rv32_console      (or %s)\n", pty_slave_path);
    }
    printf("============================================================\n\n");
    fflush(stdout);

    return 0;
}

static PLI_INT32 term_wait_client_calltf(char *user_data) {
    (void)user_data;
    vpiHandle systf_handle = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle arg_iter = vpi_iterate(vpiArgument, systf_handle);
    if (!arg_iter) return 0;
    vpiHandle conn_arg = vpi_scan(arg_iter);

    if (client_sock < 0 && server_sock >= 0) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int newsock = accept(server_sock, (struct sockaddr *)&client_addr, &client_len);
        if (newsock >= 0) {
            int flags = fcntl(newsock, F_GETFL, 0);
            fcntl(newsock, F_SETFL, flags | O_NONBLOCK);
            client_sock = newsock;
            printf("[VPI] Client connected via TCP (localhost:9000)\n");
            fflush(stdout);
        }
    }

    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = (client_sock >= 0) ? 1 : 0;
    vpi_put_value(conn_arg, &val, NULL, vpiNoDelay);

    return 0;
}

static PLI_INT32 term_tx_calltf(char *user_data) {
    (void)user_data;
    vpiHandle systf_handle = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle arg_iter = vpi_iterate(vpiArgument, systf_handle);
    if (!arg_iter) return 0;

    vpiHandle byte_arg = vpi_scan(arg_iter);

    s_vpi_value val;
    val.format = vpiIntVal;
    vpi_get_value(byte_arg, &val);

    char c = (char)(val.value.integer & 0xFF);

    if (pty_master >= 0) {
        (void)write(pty_master, &c, 1);
    }
    if (client_sock >= 0) {
        (void)send(client_sock, &c, 1, 0);
    }
    return 0;
}

static PLI_INT32 term_poll_rx_calltf(char *user_data) {
    (void)user_data;
    vpiHandle systf_handle = vpi_handle(vpiSysTfCall, NULL);
    vpiHandle arg_iter = vpi_iterate(vpiArgument, systf_handle);
    if (!arg_iter) return 0;

    vpiHandle data_arg  = vpi_scan(arg_iter);
    vpiHandle valid_arg = vpi_scan(arg_iter);

    // Accept incoming TCP connection if pending
    if (server_sock >= 0 && client_sock < 0) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int newsock = accept(server_sock, (struct sockaddr *)&client_addr, &client_len);
        if (newsock >= 0) {
            int flags = fcntl(newsock, F_GETFL, 0);
            fcntl(newsock, F_SETFL, flags | O_NONBLOCK);
            client_sock = newsock;
            printf("[VPI] Client connected via TCP (localhost:9000)\n");
            fflush(stdout);
        }
    }

    char c = 0;
    int got_byte = 0;

    if (client_sock >= 0) {
        ssize_t n = recv(client_sock, &c, 1, 0);
        if (n > 0) {
            got_byte = 1;
        } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
            close(client_sock);
            client_sock = -1;
            printf("[VPI] Client disconnected from TCP terminal\n");
            fflush(stdout);
        }
    }

    if (!got_byte && pty_master >= 0) {
        ssize_t n = read(pty_master, &c, 1);
        if (n > 0) {
            got_byte = 1;
        }
    }

    s_vpi_value val_data, val_valid;
    val_data.format = vpiIntVal;
    val_valid.format = vpiIntVal;

    if (got_byte) {
        val_data.value.integer = (unsigned char)c;
        val_valid.value.integer = 1;
    } else {
        val_data.value.integer = 0;
        val_valid.value.integer = 0;
    }

    vpi_put_value(data_arg, &val_data, NULL, vpiNoDelay);
    vpi_put_value(valid_arg, &val_valid, NULL, vpiNoDelay);

    return 0;
}

static s_vpi_systf_data tf_data[4];

void register_pty_bridge(void) {
    memset(tf_data, 0, sizeof(tf_data));

    tf_data[0].type      = vpiSysTask;
    tf_data[0].tfname    = "$term_init";
    tf_data[0].calltf    = term_init_calltf;

    tf_data[1].type      = vpiSysTask;
    tf_data[1].tfname    = "$term_tx";
    tf_data[1].calltf    = term_tx_calltf;

    tf_data[2].type      = vpiSysTask;
    tf_data[2].tfname    = "$term_poll_rx";
    tf_data[2].calltf    = term_poll_rx_calltf;

    tf_data[3].type      = vpiSysTask;
    tf_data[3].tfname    = "$term_wait_client";
    tf_data[3].calltf    = term_wait_client_calltf;

    vpi_register_systf(&tf_data[0]);
    vpi_register_systf(&tf_data[1]);
    vpi_register_systf(&tf_data[2]);
    vpi_register_systf(&tf_data[3]);
}

void (*vlog_startup_routines[])(void) = {
    register_pty_bridge,
    0
};
