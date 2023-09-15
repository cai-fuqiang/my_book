for PATCH_FILE in `ls -l ./*.patch |awk '{print $8}'`
do
	md_file=`echo $PATCH_FILE |sed 's/patch$/md/g'`
        mv $PATCH_FILE $md_file
done
