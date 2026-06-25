:loop
ncat -l 6666 -k -e "ncat 127.0.0.1 5672"
timeout 20
goto loop