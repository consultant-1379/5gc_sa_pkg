#!/usr/bin/python

from multiprocessing import Pool
import os, sys, time
import uuid

 
def create_volume(name, size, image=None):
    cmd = "cinder create --name {0} {1}".format(name, size)
    if isinstance(image, basestring):
        cmd += " --image " + image
    print("Info: Execute command: {0}".format(cmd))
    os.popen(cmd)

def delete_volume(name):
    os.popen("cinder delete {0}".format(name))


def check_avail_volumes(prefix=""):
    avail_volume_num = os.popen("cinder list | grep {0} | awk '{{if($4==\"available\") print $6}}' | wc -l".format(prefix)).read().strip('\n')
    return avail_volume_num.isdigit() and int(avail_volume_num) == count
 

if __name__=='__main__':

    batch_id = str(uuid.uuid4())[:8]
    prefix = "test-slow-volume-creation-{0}-".format(batch_id)
    image = None
    count = 6
    args=sys.argv[1:]
    if len(args) == 1:
        if args[0].isdigit():
            count = int(args[0])
        else:
            image = sys.argv[1]
    elif len(args) == 2:
        image = args[0]
        count = int(args[1]) if args[1].isdigit() else count
        
    volume_size = 10
    p_create = Pool(count)
    print("Creating {0} volume.".format(count))
    for i in range(count):
        volume_name = prefix + str(i)
        p_create.apply_async(create_volume, args=(volume_name, volume_size, image))
    p_create.close()
    p_create.join()

    start = time.time()
    retry_count = 0
    max_retry_count = 120
    create_fail = False
    while not check_avail_volumes(prefix):
        print("RETRY {} to check if all volume complete...".format(str(retry_count)))
        if retry_count > max_retry_count - 1:
            create_fail = True
            print("Error: Exceed max retry times for volume status check, delete volumes manually.")
            break
        time.sleep(1)
        retry_count += 1
    else:
        finish =  time.time()
        print('-------------------------------------------')
        print('{0} volumes creation takes {1:.1f} seconds.'.format(count, (finish - start)))
        print('-------------------------------------------')

        print("Deleting {0} volumes.".format(count))
        p_delete = Pool(count)
        for j in range(count):
            volume_name = prefix + str(j)
            p_delete.apply_async(delete_volume, args=(volume_name,))
        p_delete.close()
        p_delete.join()

    if create_fail:
        delete_volume_cmds="""
## Run the below command to delete all created volumes including failed volumes ##
all_volumes=$(cinder list | grep -E "\stest-slow-volume-creation-[a-z0-9]{8}-[0-9]+\s")
not_available_volumes=$(echo "$all_volumes" | awk '{if($4!="available") print $2}')
cinder delete $(echo "$all_volumes" | awk '{print $2}')
[[ "$not_available_volumes" ]] && cinder reset-state --state available "$not_available_volumes" && cinder delete "$not_available_volumes"
"""
        print(delete_volume_cmds)
