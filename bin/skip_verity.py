#!/usr/bin/env python3


# This script is oppo r7plusm only
# Except we can skip verity whtn flash via twrp
def skip_verity(updater_script: str):
    """
    Replace 7plusf -> 7Plusm
    Replace oppo.verify_trustzone("TZ.BF.3.0.C3.1-00001") == "1" -> "1" == "1"
    """
    def calc_delete_size(buf:str):
        # calc quote
        quote = 0
        meet = False
        size = 0
        while True:
            if meet and quote == 0: break
            if buf[size] == '(':
                if not meet: meet = not meet
                quote += 1
            if buf[size] == ')':
                quote -= 1
            size += 1

        while True:
            if buf[size] == ";": break
            size += 1

        return size + 1

    def remove_segment(buf, index, size):
        if index == 0: return buf[size:]
        return buf[:index] + buf[index + size:]

    with open(updater_script, "r+", newline='\n') as f:
        buf = f.read()
        while True:
            index = buf.find('assert(')
            if index == -1:
                break
            size = calc_delete_size(buf[index:])
            buf = remove_segment(buf, index, size)
    
        # MOKEE USE THIS
        buf = buf.replace(r'oppo.verify_trustzone("TZ.BF.3.0.C3.1-00001")', r'"1"')

        #print(buf)
        f.truncate(0)
        f.seek(0, 0)
        f.write(buf)


if __name__ == "__main__":
    import sys

    skip_verity(sys.argv[1])