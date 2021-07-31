pragma solidity 0.6.12;

import '@fuzzfinance/fuzz-swap-lib/contracts/token/HRC20/IHRC20.sol';
import '@fuzzfinance/fuzz-swap-lib/contracts/token/HRC20/SafeHRC20.sol';
import '@fuzzfinance/fuzz-swap-lib/contracts/access/Ownable.sol';

import './MasterChef.sol';

contract LotteryRewardPool is Ownable {
    using SafeHRC20 for IHRC20;

    MasterChef public chef;
    address public adminAddress;
    address public receiver;
    IHRC20 public lptoken;
    IHRC20 public fuzz;

    constructor(
        MasterChef _chef,
        IHRC20 _fuzz,
        address _admin,
        address _receiver
    ) public {
        chef = _chef;
        fuzz = _fuzz;
        adminAddress = _admin;
        receiver = _receiver;
    }

    event StartFarming(address indexed user, uint256 indexed pid);
    event Harvest(address indexed user, uint256 indexed pid);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    function startFarming(uint256 _pid, IHRC20 _lptoken, uint256 _amount) external onlyAdmin {
        _lptoken.safeApprove(address(chef), _amount);
        chef.deposit(_pid, _amount);
        emit StartFarming(msg.sender, _pid);
    }

    function  harvest(uint256 _pid) external onlyAdmin {
        chef.deposit(_pid, 0);
        uint256 balance = fuzz.balanceOf(address(this));
        fuzz.safeTransfer(receiver, balance);
        emit Harvest(msg.sender, _pid);
    }

    function setReceiver(address _receiver) external onlyAdmin {
        receiver = _receiver;
    }

    function  pendingReward(uint256 _pid) external view returns (uint256) {
        return chef.pendingFuzz(_pid, address(this));
    }

    // EMERGENCY ONLY.
    function emergencyWithdraw(IHRC20 _token, uint256 _amount) external onlyOwner {
        fuzz.safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    function setAdmin(address _admin) external onlyOwner {
        adminAddress = _admin;
    }

}
