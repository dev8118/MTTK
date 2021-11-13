// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Ownable {
    address public owner;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Required only owner!");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract MyTestToken is Ownable, ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    uint256 private immutable _cap;
    uint256 public burningPercentageRate;
    uint256 public lpPercentageFee;
    
    address private _wethTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private _uniFactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private _uniRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    
    uint256 private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;
    
    constructor(uint256 cap_) ERC20("MyTestToken", "MTTKN"){
        _cap = cap_ * 10 ** decimals();
    }
    
    function cap() public view virtual returns (uint256) {
        return _cap;
    }
        
    function _mint(address account, uint256 amount) internal override {
        require(ERC20.totalSupply() + amount <= cap(), "MTTKN: cap exceeded");
        console.log(account, " minted ", amount);
        super._mint(account, amount);
    }
    
    function _isTrade(address sender, address recipient) private view returns(bool) {
        return sender == _uniRouterAddress || recipient == _uniRouterAddress;
    }
    
    function mint(uint256 amount) public onlyOwner {
        _mint(owner, amount);
    }
    
    function mintTo(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }
    
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
    
    function burnFrom(address account, uint256 amount) public {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "MTTKN: burn amount exceeds allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);
    }
    
    function setBurningPercentageRate(uint256 rate) public onlyOwner {
        require(rate >= 0 && rate <= 10000, "MTTKN: burning percentage rate is out ranged");
        burningPercentageRate = rate;
    }
    
    function setLpPercentageFee(uint256 rate) public onlyOwner {
        require(rate >= 0 && rate <= 10000, "MTTKN: lp percentage fee rate is out ranged");
        lpPercentageFee = rate;
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        uint256 balance = balanceOf(sender);
        require(amount <= balance, "MTTKN: transfer amount exceeds balance");
        
        uint256 burnAmt = amount * burningPercentageRate / 10000; 
        uint256 feeAmt = 0;
        
        if(_isTrade(sender, recipient)) {
            feeAmt = amount * lpPercentageFee / 10000;
            //add tokens into liquidity pool(token - weth)
            _addLiquidityTokens(feeAmt);
        }
        
        super._transfer(sender, recipient, amount - burnAmt - feeAmt);
        _burn(sender, burnAmt);
    }
    
    function _addLiquidityTokens(uint256 amount_) internal returns (uint256, uint256){
        IUniswapV2Factory uniFactory = IUniswapV2Factory(_uniFactoryAddress);
        address uniPairAddress = uniFactory.getPair(address(this), _wethTokenAddress);
        if(uniPairAddress == address(0)) {
            uniPairAddress = uniFactory.createPair(address(this), _wethTokenAddress);
        }
        IUniswapV2Pair uniPair = IUniswapV2Pair(uniPairAddress);
        (uint256 res0, , ) = uniPair.getReserves();
        
        //calculate amount to swap with WETH
        uint256 amtToSwap = calculateSwapInAmount(res0, amount_);
        if(amtToSwap <= 0) amtToSwap = amount_ / 2;
        
        //swap token to weth
        uint256 wethBought = _tokenToToken(address(this), _wethTokenAddress, uniPairAddress, amtToSwap);
        return (amount_ - amtToSwap, wethBought);
    }
    
    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn) internal pure returns (uint256){
        return Babylonian.sqrt(reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))).sub(reserveIn.mul(1997)) / 1994;
    }
    
    function _tokenToToken(address tokenAddress0, address tokenAddress1, address uniPairAddress, uint256 tokensToTrade) internal returns (uint256) {
        if(tokenAddress0 == tokenAddress1) {
            return tokensToTrade;
        }
        IERC20(address(this)).safeApprove(address(_uniRouterAddress), 0);
        IERC20(address(this)).safeApprove(address(_uniRouterAddress), tokensToTrade);
        
        require(uniPairAddress != address(0), "No Swap Available");
        
        //swapping 
        address[] memory path = new address[](2);
        path[0] = tokenAddress0;
        path[1] = tokenAddress1;
        
        uint256 tokenBought = IUniswapV2Router02(_uniRouterAddress).swapExactTokensForTokens(tokensToTrade, 1, path, address(this), deadline)[path.length - 1];
        
        require(tokenBought > 0, "Error Swapping Tokens 2");
        
        return tokenBought;
    }
}
 
