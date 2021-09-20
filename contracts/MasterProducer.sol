pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./ReverbStudio.sol";
import "./FuzzToken.sol";
import "./FuzzStaking.sol";

// MasterProducer is the master of Fuzz. He can make Fuzz and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once FUZZ is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterProducer is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastPendingFuzz; // Stored staking rewards. Stored when staking totals are updated.
        //
        // We do some fancy math here. Basically, any point in time, the amount of FUZZs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accFuzzPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accFuzzPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. FUZZs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that FUZZs distribution occurs.
        uint256 accFuzzPerShare; // Accumulated FUZZs per share, times 1e12. See below.
    }

    // The FUZZ TOKEN!
    FuzzToken public fuzz;
    // The REVERB TOKEN!
    ReverbStudio public reverb;
    // Contract used to populate staking amounts
    FuzzStaking public stakingContract;
    // Dev address.
    address public devaddr;
    // FUZZ tokens created per block.
    uint256 public fuzzPerBlock;
    // Bonus muliplier for early fuzz makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    //IMigratorChef public migrator;
    
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when FUZZ mining starts.
    uint256 public startBlock;
    
        // Bonus muliplier for early GovernanceToken makers.
    uint256[] public REWARD_MULTIPLIER; // init in constructor function
    uint256[] public HALVING_AT_BLOCK; // init in constructor function
    
    // Staking Variables
    uint256 public UNDER_MIN_REWARD = 1000;
    uint256 public MAX_STAKING_REWARD = 20000;
    uint256 public MIN_STAKING_REWARD = 5000;
    uint256 public STAKING_REWARD_STEP = 25;
    uint256 public MIN_STAKING_AMOUNT = 10000 ether;
    uint256 public STAKING_SPLIT = 10000 ether;
    uint256 public EXPONENTIAL = 100000;
    bool public stakingRewardActive;
    
    function setStakingReward() public onlyOwner {
        stakingRewardActive = !stakingRewardActive;
    }
    
    function updateStakingVariables(uint256 _UNDER_MIN_REWARD, uint256 _MAX_STAKING_REWARD, uint256 _MIN_STAKING_REWARD, uint256 _STAKING_REWARD_STEP, uint256 _MIN_STAKING_AMOUNT, uint256 _STAKING_SPLIT) public onlyOwner {
        UNDER_MIN_REWARD = _UNDER_MIN_REWARD;
        MAX_STAKING_REWARD = _MAX_STAKING_REWARD;
        MIN_STAKING_REWARD = _MIN_STAKING_REWARD;
        STAKING_REWARD_STEP = _STAKING_REWARD_STEP;
        MIN_STAKING_AMOUNT = _MIN_STAKING_AMOUNT;
        STAKING_SPLIT = _STAKING_SPLIT;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        FuzzToken _fuzz,
        ReverbStudio _reverb,
        FuzzStaking _stakingContract,
        address _devaddr,
        uint256 _fuzzPerBlock,
        uint256 _startBlock,
        uint256 [] memory _REWARD_MULTIPLIER,
        uint256 [] memory _HALVING_AT_BLOCK
    ) {
        fuzz = _fuzz;
        reverb = _reverb;
        devaddr = _devaddr;
        fuzzPerBlock = _fuzzPerBlock;
        startBlock = _startBlock;
        stakingContract = _stakingContract;
        stakingRewardActive = true;
        REWARD_MULTIPLIER = _REWARD_MULTIPLIER;
        HALVING_AT_BLOCK = _HALVING_AT_BLOCK;
        
               // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _fuzz,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accFuzzPerShare: 0
        }));

        totalAllocPoint = 1000;
    }
    
    /// STAKING FUNCTIONS ///
    
    function updateStakingContract(address _stakingContract) public onlyOwner {
        stakingContract = FuzzStaking(_stakingContract);
    }
    
    function pushPendingFuzzToStorage(address[] memory stakingAddresses) public onlyOwner {
        for(uint i = 0; i < stakingAddresses.length; i++){
                address _user = stakingAddresses[i];
            for(uint x = 1; x < this.poolLength(); x++){
                uint _pid = x;
                UserInfo storage user = userInfo[_pid][_user];
                if(user.amount > 0){
                uint256 pendingRewards = pendingStakingRewards(x, stakingAddresses[i]);
                if(pendingRewards > 0){
                    user.lastPendingFuzz = pendingRewards.add(user.lastPendingFuzz);
                }
                }
                
            }

        }
    }
    
    function pendingStakingRewards(uint _pid, address _user) public view returns (uint256) {
        
        uint256 balanceDelta = 0;
        UserInfo storage user = userInfo[_pid][_user];
        if(!(isStaked(_user)) && user.lastPendingFuzz == 0) return 0;
        uint256 multiplier = getStakingMultiplier(_user);
        uint256 pendingBalance = this.pendingFuzz(_pid, _user);
        uint256 pendingRewards = pendingBalance.mul(multiplier).div(EXPONENTIAL);
        if(pendingRewards > user.lastPendingFuzz){
        balanceDelta = pendingRewards.sub(user.lastPendingFuzz);
        } else {
        balanceDelta = user.lastPendingFuzz.add(pendingRewards);
        }

        return balanceDelta;
    }
    
        function isStaked(address _user) public view returns (bool) {
        return stakingContract.isStaked(_user);
    }
    
    function getStakingMultiplier(address _user) public view returns (uint256) {
        if(!isStaked(_user)) return 0;
        uint stakedAmount = stakingContract.viewDelegationAmount(_user);
        if(stakedAmount == 0) return 0;
        if(stakedAmount < MIN_STAKING_AMOUNT) return UNDER_MIN_REWARD;
        uint256 percent = uint(stakedAmount.div(STAKING_SPLIT)).mul(STAKING_REWARD_STEP);
        uint256 finalPercent = MIN_STAKING_REWARD.add(percent);
        if(finalPercent >= MAX_STAKING_REWARD) return MAX_STAKING_REWARD;
        return finalPercent;
    }
    
    function getBlock() public view returns (uint256) {
        return block.number;
    }
    
    /////////////////////////

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accFuzzPerShare: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's FUZZ allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    //function migrate(uint256 _pid) public {
    //    require(address(migrator) != address(0), "migrate: no migrator");
    //    PoolInfo storage pool = poolInfo[_pid];
    //    IERC20 lpToken = pool.lpToken;
    //    uint256 bal = lpToken.balanceOf(address(this));
    //    lpToken.safeApprove(address(migrator), bal);
    //    IERC20 newLpToken = migrator.migrate(lpToken);
    //    require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
    //    pool.lpToken = newLpToken;
    //}
    
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 result = 0;
        if (_from < startBlock) return 0;
        if (HALVING_AT_BLOCK[HALVING_AT_BLOCK.length-1] < block.number) return _to.sub(_from).mul(BONUS_MULTIPLIER);

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];

            if (_to <= endBlock) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endBlock) {
                uint256 m = endBlock.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endBlock;
                result = result.add(m);
            }
        }

        return result;
    }

    // View function to see pending FUZZs on frontend.
    function pendingFuzz(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accFuzzPerShare = pool.accFuzzPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 fuzzReward = multiplier.mul(fuzzPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accFuzzPerShare = accFuzzPerShare.add(fuzzReward.mul(1e12).div(lpSupply));
        }
        
        return user.amount.mul(accFuzzPerShare).div(1e12).sub(user.rewardDebt);
        
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 fuzzReward = multiplier.mul(fuzzPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        fuzz.mint(devaddr, fuzzReward.div(10));
        fuzz.mint(address(reverb), fuzzReward);
        pool.accFuzzPerShare = pool.accFuzzPerShare.add(fuzzReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for FUZZ allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'deposit FUZZ by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 stakingRewards = 0;
        
        if(stakingRewardActive){
            stakingRewards = pendingStakingRewards(_pid, msg.sender);
        }
        
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accFuzzPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeFuzzTransfer(msg.sender, pending.add(stakingRewards));
                user.lastPendingFuzz = 0;
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFuzzPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'withdraw FUZZ by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        
        uint256 stakingRewards = 0;
        if(stakingRewardActive){
            stakingRewards = pendingStakingRewards(_pid, msg.sender);
        }
        
        uint256 pending = user.amount.mul(pool.accFuzzPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeFuzzTransfer(msg.sender, pending.add(stakingRewards));
            user.lastPendingFuzz = 0;
        }
        
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        
        user.rewardDebt = user.amount.mul(pool.accFuzzPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake FUZZ tokens to MasterChef
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accFuzzPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeFuzzTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFuzzPerShare).div(1e12);

        reverb.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw FUZZ tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accFuzzPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeFuzzTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accFuzzPerShare).div(1e12);

        reverb.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.lastPendingFuzz = 0;
    }

    // Safe fuzz transfer function, just in case if rounding error causes pool to not have enough FUZZs.
    function safeFuzzTransfer(address _to, uint256 _amount) internal {
        reverb.safeFuzzTransfer(_to, _amount);
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
