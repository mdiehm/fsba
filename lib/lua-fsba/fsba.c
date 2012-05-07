/*
 * Copyright (c) 2011 Mischa Diehm <md@mailq.de>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of Micro Systems Marc Balmer nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* gcc -W -Wall -pedantic -std=c99 -D_GNU_SOURCE `pkg-config --cflags lua5.1` -fPIC -shared -o fsba.so util.c */
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <errno.h>
#include <unistd.h> /* isatty, getuid */
extern int errno;

static int fsba_isatty(lua_State *L)
{
    const int val = lua_tointeger(L, 1);
    const int result = isatty(val);
    lua_pushnumber(L, result);
    lua_pushnumber(L, errno);

    return 2;
}

static luaL_Reg const pkg_funcs[] = {
    { "isatty",                     fsba_isatty },
    { NULL,                         NULL}
};

int luaopen_fsba(lua_State *L)
{
    lua_newtable(L);
    luaL_register(L, NULL, pkg_funcs);

    return 1;
}

