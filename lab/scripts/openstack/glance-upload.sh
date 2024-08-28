#!/bin/bash

set -e

PROG=glance-upload

tmpdir=$(mktemp -d /tmp/$PROG.XXXXXX)
trap "{ rm -rf $tmpdir; }" EXIT


function CleanUp()
{
  rm -rf $tmpdir
}

function info()
{
  echo Info: $@
}

function convert_to_raw()
{
  src_img=$1
  dst_img_dir=$2
  src_img_name=$3
  src_img_type=$4
  qemu-img convert -f $src_img_type -O raw $src_img ${dst_img_dir}/${src_img_name}.raw
}


function filter_same_prx_file()
{
  files_list=$@
  collect_images=()
  upload_images=()
  for i in $files_list
  do
          collect_images+=( $i )
  done
  images_others=("${collect_images[@]}")
  c=0
  for i in ${collect_images[@]}
  do
    unset images_others[$c]
    format=${i##*.}
    if [[ " ${images_others[@]} " =~ [[:blank:]]${i%.*}.* ]];then
            if [[ $format == raw ]];then
                    upload_images+=( $i )
            fi
    else
            if [[ ! " ${upload_images[@]} " =~ " ${i} " ]];then
                    upload_images+=( $i )
            fi
    fi
    let c++
  done
  echo ${upload_images[@]}
}


function check_glance_image()
{
  image=$1
  glance image-list | grep -q -oP "[[:space:]]${image}[[:space:]]"
}

function upload_image()
{
  input=$1
  input_name=${input##*/}
  image_name=${input_name%.*}
  image_format=${input_name##*.}
  image_file=$input
  image_dir=$(dirname $image_file)
  #df=${input##*.}
  df=raw
  [ $image_format == img ] && image_format=qcow2
  if [[ $image_format != $(qemu-img info $input | grep 'file format:' | awk '{print $3}') ]];then
          echo Error: The image $input is invalid format.
          exit 1
  fi

  if [ "$image_format" != raw ];then
    info Converting image $input to raw format
    convert_to_raw $image_file $tmpdir $image_name $image_format
    image_file=${tmpdir}/${image_name}.$df
  fi

  if [ $? -eq 0 ];then
    if check_glance_image $image_name;then
      echo Warning: The image $image_name already exists in Glance, skip it...
      return
    fi
    info Uploading image $image_file to glance...
    glance image-create \
     --name $image_name \
     --file $image_file \
     --disk-format $df --container-format bare \
     --progress
    [ $? -eq 0 ] && echo Finshed uploading image $image_file
  fi

}


function main()
{
  if [ $# -ge 1 ];then
    input=$@

    if [ -d $1 ];then
      image_dir=$1
      images=$(find $image_dir -maxdepth 1 -type f -name '*.qcow2' -o -name '*.raw' -o -name '*.img')
      for image in $(filter_same_prx_file $images)
      do
        upload_image $image
      done
      return $?
    fi

    for i in $input
    do
      [ -f "$i" ] && upload_image $i
    done
  else
    echo -e Usage: $PROG '<IMAGE_FILE1> [IMAGE_FILE2] ...'
    echo -e '\t\t\t  <IMAGE_DIRECTORY>'
  fi
}

main $@

# cleanup temp files
CleanUp
