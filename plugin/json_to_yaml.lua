-- json_to_yaml.lua — :ToYaml 把 JSON 转成便于阅读的 YAML
--
-- 后端复用 ~/.shell/tools/json2yaml.py（PEP 723，依赖 pyyaml）：长文本走 block scalar、
-- 保持字段原序、不转义中文。转换是无损的（YAML 是 JSON 的超集）。
--
--   :ToYaml        转换当前 buffer（或可视选择的行）→ 在新 split 中预览 YAML，不落盘
--   :ToYaml!       同上，并写入同目录同名 .yaml 文件后打开
--
-- 可用 vim.g.json_to_yaml_script 指定脚本路径，
-- 或 vim.g.json_to_yaml_cmd 指定完整命令列表（如 {'python3', '/path/to/json2yaml.py', '-'}）。

local default_script = vim.fn.expand('~/.shell/tools/json2yaml.py')

--- 构造使用的命令（末尾必须以 '-' 结尾，表示从 stdin 读、写 stdout）。
local function build_cmd()
    if vim.g.json_to_yaml_cmd then
        return vim.g.json_to_yaml_cmd
    end
    local script = vim.g.json_to_yaml_script or default_script
    if vim.fn.executable('uv') == 1 then
        -- uv run --script 会按 PEP 723 元数据自动准备 pyyaml
        return { 'uv', 'run', '--script', script, '-' }
    end
    return { 'python3', script, '-' }
end

--- 把 JSON 文本交给脚本，返回 YAML 文本；失败时返回 nil 与错误信息。
local function json_to_yaml(text)
    local out = vim.fn.system(build_cmd(), text)
    if vim.v.shell_error ~= 0 then
        return nil, vim.trim(out)
    end
    return out
end

local function to_yaml(opts)
    local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
    local yaml, err = json_to_yaml(table.concat(lines, '\n'))
    if not yaml then
        vim.notify('ToYaml: ' .. (err ~= '' and err or '转换失败'), vim.log.levels.ERROR)
        return
    end

    -- 与脚本的 src.with_suffix('.yaml') 一致：去掉原扩展名再加 .yaml
    local src = vim.api.nvim_buf_get_name(0)
    local dst = src ~= '' and (vim.fn.fnamemodify(src, ':r') .. '.yaml') or nil

    if opts.bang then
        if not dst then
            vim.notify('ToYaml: 当前 buffer 没有文件，无法确定输出路径（去掉 ! 可只预览）',
                vim.log.levels.ERROR)
            return
        end
        vim.fn.writefile(vim.split(yaml, '\n', { plain = true }), dst)
        vim.cmd.edit(vim.fn.fnameescape(dst))
        vim.notify('ToYaml: ' .. dst)
        return
    end

    vim.cmd.vnew()
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].buflisted = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(yaml, '\n', { plain = true }))
    vim.bo[buf].filetype = 'yaml'
    vim.bo[buf].modified = false
end

vim.api.nvim_create_user_command('ToYaml', function(cmd)
    to_yaml({
        bang = cmd.bang,
        line1 = cmd.range > 0 and cmd.line1 or 1,
        line2 = cmd.range > 0 and cmd.line2 or vim.api.nvim_buf_line_count(0),
    })
end, {
    range = '%',
    bang = true,
    desc = '把当前 JSON 转成 YAML（!: 写入同名 .yaml 文件）',
})