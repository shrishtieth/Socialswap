/* SPDX-License-Identifier: MIT License */

pragma solidity ^0.8.0;

import './Staking.sol';

contract ClaimReward {
    using SafeTRC20 for ITRC20;
    using _SafeMath for uint256;


    address public owner;
    ITRC20 public SST_token;
    Staking public  _Staking;

    uint256 public decimals =8;
    uint256 public _rewardDistributed;

    // reward timeline
    uint256 public reward_timeline;


    // reward levels
    uint[] public reward_levels;



    // Balance needed for each reward level
    uint[] public correspondingRewardsBalance;


    // owner 
    mapping(address => uint256 ) public ClaimableTokens; 
    mapping(address => uint256) public Eligible_Stakes; // pushed from backend how much stake user is eligible in one month

    // total refunds
    mapping(address => uint256) public ClaimedTokens;
    

    constructor(address _token, address Staking_) {
        owner = msg.sender; 
        SST_token = ITRC20(_token);
        _Staking=Staking(Staking_);
    }
    
    function updateStaking(address stakingAddress) external onlyOwner{
        _Staking = Staking(stakingAddress);
    }

    function updateOwner(address newOwner) external onlyOwner{
        owner = newOwner;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public onlyOwner{
       ITRC20(_token).transfer( _to, _amount) ; 
    }

    // for user to claim Reward

    function claimReward() external {
        require(ClaimableTokens[msg.sender] > 0 , "Amount of Claimable Tokens is 0");
        require(_Staking._balance_SST(msg.sender) >= correspondingRewardsBalance[0], "User is not eligible for rewards" );
        require(Eligible_Stakes[msg.sender] >= correspondingRewardsBalance[0], "Should have a minimum witholding period of 1 month ");

        uint256 refund_amount= calculateRefund(ClaimableTokens[msg.sender],Eligible_Stakes[msg.sender],msg.sender);

        if(refund_amount == 0 ) revert();
        SST_token.safeTransfer(msg.sender, refund_amount);

        _rewardDistributed=_rewardDistributed.add(refund_amount);
        ClaimedTokens[msg.sender]=ClaimedTokens[msg.sender].add(refund_amount);
        ClaimableTokens[msg.sender] =0;
        Eligible_Stakes[msg.sender] =0;

        emit AirdropProcessed(msg.sender,refund_amount,block.timestamp);
    }

    /*
                            Reward structure
                            {
                                user: address,
                                claimable_tokens: no. of tokens spent in one month,
                                stakes: amount of eligible stakes for reward
                            }
                            
    */

    function updateRewards(        
        address[] memory _addresses, 
        uint256[] memory tokens, 
        uint256[] memory stakes) 
        external onlyOwner{

            for(uint i=0;i<_addresses.length;++i){
                address _address= _addresses[i];
                uint256 claimable_tokens= tokens[i];
                uint256 total_stakes= stakes[i];

                Eligible_Stakes[_address] = total_stakes;
                ClaimableTokens[_address] = claimable_tokens;
            }

    }

    function refund_percentage(uint256 tokens,uint refund_percent)internal pure returns(uint){
        return (tokens.mul(refund_percent.mul(100))).div(10000);

    }
    
    // Calculates how much refund a user can earn on the basis of no. of stakes for the number of tokens as input 
    // example===     tokens=100 and _stakes=100*10**decimals then refund should be the reward_level percent  as per the return refund percentage policy.

    function calculateRefund(uint256 tokens,uint256 _stakes,address person) public view returns(uint256){
        require(_Staking._balance_SST(person) >= correspondingRewardsBalance[0],'Minimum amount of Staking balance not satisfied');

        uint256 return_refund=0;
        uint length=reward_levels.length;

        for(uint i=0;i<length-1;++i){
            if(_stakes >= correspondingRewardsBalance[i] && _stakes< correspondingRewardsBalance[i+1]) return_refund= refund_percentage(tokens,reward_levels[i]);
        }

        if(_stakes >= correspondingRewardsBalance[length-1]) return_refund=refund_percentage(tokens,reward_levels[length-1]);

        return return_refund;
    }


    //Calculates the eligible Stakes 
    function Calc_EligibleStakes(address _address) public view returns(uint256){
        (uint256[] memory StakedTime,uint256[] memory StakedAmount,bool[] memory isActive) = _Staking.getAllStakes(_address);

        uint256 total_Stakes=0;

        for(uint256 i=0;i<StakedTime.length;++i){
           if(! isActive[i]) continue;

           if((block.timestamp - StakedTime[i]) > (reward_timeline.mul(86400)) ) total_Stakes= total_Stakes.add(StakedAmount[i]); 
        }

        return total_Stakes;


    }

    function resetRewards(uint[] memory rewardspercentlist,uint[] memory _correspondingRewardsBalance) external onlyOwner{
        require(rewardspercentlist.length == _correspondingRewardsBalance.length,"Both lists should be of equal size");
        delete reward_levels;
        delete correspondingRewardsBalance;
        reward_levels= rewardspercentlist;
        correspondingRewardsBalance=_correspondingRewardsBalance;
    }


    // Calculates user is eligible for how much Refund in percentage
    function Calc_Eligible_RefundPercent(address _address) external view returns(uint256){
        uint256 _eligibleStakes=Calc_EligibleStakes(_address);
        return Calc_RefundAsPerStakes(_eligibleStakes);
   
    }


    //Calculate the refund as per the amount of stake 
    function Calc_RefundAsPerStakes(uint256 _eligibleStakes) public view returns(uint256){
        if(_eligibleStakes < correspondingRewardsBalance[0] ) return 0;

        uint length=correspondingRewardsBalance.length;

        for(uint i=0;i<length-1;++i){
            if(_eligibleStakes >= correspondingRewardsBalance[i] && _eligibleStakes < correspondingRewardsBalance[i+1]) return reward_levels[i];
        }

        if(_eligibleStakes >= reward_levels[length-1]) return reward_levels[length-1];
        return 0;

    } 

    // Set the timeline of the rewards
    function SetRewardTimeline(uint256 _newTimeline)external onlyOwner{
        reward_timeline= _newTimeline;
    }


    function updateDecimals(uint256 _decimals) external onlyOwner{
        decimals=_decimals;
    }


    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    function _onlyOwner() private view {
        require(msg.sender == owner, "Only the contract owner may perform this action");
    }

    event AirdropProcessed(
        address recipient,
        uint amount,
        uint date
    );

}
