--!strict

local M = {};

type Props = {
  walk_speed: number,
}

local props: Props = {
  walk_speed = 10,
}

M.props = props;

function M.update(delta_time: number)
  local speed_x = get_this_mob_speed_x()
  if (speed_x == 0) then
    set_this_mob_speed_x(M.props.walk_speed)
  end
end

return M;
