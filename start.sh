#!/bin/sh
# echo /usr/local/ev_sdk  > /etc/lb.conf
# 环境变量介绍
# ---------------- 仓库 -----------------
# USER_EMAIL： 用户邮箱 
# USERNAME： 用户名
# SRC_GIT_URL： 训练代码src_repo对应仓库地址
# SDK_GIT_URL： 原始模型的ev sdk的git对应仓库地址
# IS_OPENVINO_EV_SDK_IMAGE：当前镜像是否为OpenVINO EV_SDK镜像，设置此环境变量表示为OpenVINO EV_SDK，反之不是
# --------- Jupyter & VSCode -----------
# JUPYTER_TOKEN： jupyter的token
# JUPYTER_URI： jupyter的网址对应的中间location  例如 JUPYTER_URI=v1   http://192.168.1.15:31236/v1/lab?  
# VSCODE_URI： vscode的url要跟jupyter的一致。  例如jupyter是 v1  那么vscode的就是 /v1/vscode/ 一定要把斜线都补上
# PASSWORD：(暂时无用)，给vscode增加密码
# --------------- 镜像信息 --------------
# BASE_IMAGE_NAME： 基础镜像名称
# EV_SDK_IMAGE_NAME: EV_SDK基础镜像名称
# WORKSPACE_IMAGE_NAME: 编码环境基础镜像名称
# IS_START_URL: 回调后端此镜像是否启动的地址

git config --global user.email "$USER_EMAIL"
git config --global user.name "$USERNAME"

# 项目目录
project_dir=/project
key=$project_dir/.ssh/key

mkdir -p $project_dir
mkdir -p $project_dir/.ssh

# 复制私钥
if [ ! -f $key ]
then
	cat /home/secret/gitlab_private_key > $key
	chmod 400 $key
fi

demo_dir=/project-demo

# 首次移动项目到挂载目录中
if [ ! -z ${IS_OPENVINO_EV_SDK_IMAGE} ]; then
	if [ ! -f /usr/local/ev_sdk/.createdir ]; then
		# 将OpenVINO示例sdk移动到/usr/local/ev_sdk，并创建软连接到/project/ev_sdk
		bash -c "shopt -s dotglob nullglob;mv ${demo_dir}/openvino_ev_sdk/* /usr/local/ev_sdk/"
		echo 此文件请不动 >> /usr/local/ev_sdk/.createdir
	fi
else
	if [ ! -f /usr/local/ev_sdk/.createdir ]; then
		# 将简易版sdk移动到/usr/local/ev_sdk，并创建软连接到/project/ev_sdk
		bash -c "shopt -s dotglob nullglob;mv ${demo_dir}/ev_sdk/* /usr/local/ev_sdk/"
		echo 此文件请不动 >> /usr/local/ev_sdk/.createdir
	fi
fi
if [ ! -f ${project_dir}/train/.createdir ]; then
	# 将Demo训练代码移动到/project/train下
	bash -c "shopt -s dotglob nullglob; mv ${demo_dir}/train/* /project/train/"
	echo 此文件请不动 >> ${project_dir}/train/.createdir
fi

ev_sdk_dir=${project_dir}/ev_sdk

if [ ! -L ${ev_sdk_dir} ]; then
	ln -s /usr/local/ev_sdk ${ev_sdk_dir}
fi

if [ -z ${EV_SDK_IMAGE_NAME} ]; then
	# Compatable to old env
	sed -i "s|FROM .*|FROM ${BASE_IMAGE_NAME}|" ${ev_sdk_dir}/Dockerfile
else
	sed -i "s|FROM .*|FROM ${EV_SDK_IMAGE_NAME}|" ${ev_sdk_dir}/Dockerfile
fi
if [ ! -d $ev_sdk_dir/.git ]; then
	cd $ev_sdk_dir
	git init
	git config remote.origin.url $SDK_GIT_URL
	git config core.sshCommand "ssh  -o stricthostkeychecking=no $key"
	git pull
	git add -f .
	git commit -m "Demo first commit"
	git push --set-upstream origin master
	git push
else
	cd ${ev_sdk_dir}
	git config remote.origin.url ${SDK_GIT_URL}
	git config core.sshCommand "ssh  -o stricthostkeychecking=no $key"
fi

# 初始化源代码的git仓库
src_dir=$project_dir/train/src_repo

if [ -z ${WORKSPACE_IMAGE_NAME} ]; then
	# Compatable to old env
	sed -i "s|FROM .*|FROM ${BASE_IMAGE_NAME}|" ${src_dir}/Dockerfile
else
	sed -i "s|FROM .*|FROM ${WORKSPACE_IMAGE_NAME}|" ${src_dir}/Dockerfile
fi
if [ ! -d $src_dir/.git ]; then
	cd $src_dir
	git init
	git config remote.origin.url $SRC_GIT_URL
	git config core.sshCommand "ssh  -o stricthostkeychecking=no $key"
	git pull
	git add .
	git commit -m "Demo first commit"
	git push --set-upstream origin master
	git push 
else
	cd ${src_dir}
	git config remote.origin.url ${SRC_GIT_URL}
	git config core.sshCommand "ssh  -o stricthostkeychecking=no $key"
fi

sed -i "s#VSCODE_URI#$VSCODE_URI#g" /etc/nginx/nginx.conf

# 拷贝用户配置文件
cp /root/.bashrc ${HOME}/
cp /root/.profile ${HOME}/

# 在zsh的配置文件中设置OpenVINO的环境变量了
# echo "source /opt/intel/openvino/bin/setupvars.sh" >> /etc/zsh/zshenv

nohup jupyter-lab --ip=0.0.0.0 --allow-root --LabApp.webapp_settings="{'headers': {'Content-Security-Policy': 'frame-ancestors self * ; report-uri /api/security/csp-report'}}"  --LabApp.base_project_url=$JUPYTER_URI --notebook-dir=$project_dir --LabApp.token=$JUPYTER_TOKEN --LabApp.quit_button=False --LabApp.file_to_run=$project_dir/Readme.ipynb &
nohup /usr/bin/code-server --port=8889 --disable-telemetry --user-data-dir=$project_dir/.config/Code/ --extensions-dir=$project_dir/.vscode/extensions/ --auth=none $project_dir &
eval $IS_START_URL
nginx
